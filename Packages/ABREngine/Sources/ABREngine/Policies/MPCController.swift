//
//  MPCController.swift
//  ABREngine
//
//  MPC（Model Predictive Control）ABR 控制器
//
//  在 BBA 安全兜底之上，用滚动时域优化选择目标码率：
//    - 预测模型：buffer(t+1) = buffer(t) + dt * (throughput/bitrate - 1)
//    - 代价函数：J = Σ [ w_stall*stallSeconds + w_quality*dt*(max-br)/max ] + w_switch*switch
//    - 求解：对每个候选档位做"保持该档位"的时域展开，取总代价最小者
//    - 安全：buffer < reservoir / 弱网 / 无吞吐观测 时强制最低档（与 BBA 一致）
//
//  时域粒度（对齐 FastMPC/RobustMPC, Yin et al. SIGCOMM '15）：
//  预测按 segment 推进（dt = segmentDuration，horizon × dt 窗口），而非按控制周期推进。
//  窗口必须显著大于 reservoir（见 ABRConfig.satisfiesHorizonConstraint）。
//

import AVFoundation
import Foundation

/// MPC（Model Predictive Control）ABR 控制器
public final class MPCController: ABRController {

    // MARK: - 参数（由 ABRConfig 注入）

    public let config: ABRConfig

    // MARK: - ABRController 协议

    public private(set) var variants: [HLSVariant]
    public private(set) var currentTarget: Double?
    public private(set) var switchCount: Int = 0
    public var simulateWeakNetwork: Bool = false
    public var onSwitch: ((SwitchLog) -> Void)?

    // MARK: - MPC 状态

    /// EWMA 吞吐估计（bps）
    private var throughputEstimator: ThroughputEstimator
    /// 当前 EWMA 吞吐（bps），供 UI 读取
    public private(set) var estimatedThroughput: Double = 0
    /// 累计代价 J，供 UI 读取
    public private(set) var cumulativeCost: Double = 0
    /// 上次 rollout 重算的时刻（播放时间轴，秒）。nil 表示还没算过。
    private var lastRolloutTime: Double?

    // MARK: - 依赖

    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?
    private var controlTimer: Timer?

    // MARK: - Init

    public init(player: AVPlayer, variants: [HLSVariant], config: ABRConfig = ABRConfig()) {
        self.player = player
        self.playerItem = player.currentItem
        self.variants = variants.sorted { $0.peakBitRate < $1.peakBitRate }
        self.config = config
        self.throughputEstimator = ThroughputEstimator(alpha: config.alpha)
    }

    deinit {
        stop()
    }

    // MARK: - 启停

    public func start() {
        guard controlTimer == nil else { return }
        controlLoop()
        let interval = config.controlLoopInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.controlLoop()
        }
        RunLoop.main.add(timer, forMode: .common)
        controlTimer = timer
    }

    public func stop() {
        controlTimer?.invalidate()
        controlTimer = nil
    }

    /// 提交决策（更新内部 currentTarget）。控制循环内自动调用；
    /// 暴露为 public 供 XCTest 逐拍重放决策序列（见 ABREngineTests）。
    public func commit(_ target: Double) {
        currentTarget = target
    }

    // MARK: - 控制循环

    public func controlLoop() {
        guard let playerItem = playerItem ?? player?.currentItem else { return }
        guard !variants.isEmpty else { return }

        let bufferSeconds = computeBufferSeconds(from: playerItem)
        let observed = observedBitrate(from: playerItem)
        if observed > 0 {
            estimatedThroughput = throughputEstimator.feed(observed: observed)
        }

        let currentBR = currentTarget ?? variants.first!.peakBitRate
        let now = playerItem.currentTime().seconds
        let dueForRollout = shouldRecomputeRollout(at: now)
        let targetBitrate = decide(bufferSeconds: bufferSeconds,
                                   estimatedThroughput: estimatedThroughput,
                                   currentBitrate: currentBR,
                                   recomputeRollout: dueForRollout)

        if targetBitrate != currentTarget {
            let fromBR = currentTarget ?? 0
            let reason = switchReason(bufferSeconds: bufferSeconds,
                                      from: fromBR, to: targetBitrate,
                                      throughput: estimatedThroughput)
            let log = SwitchLog(timestamp: Date(),
                                fromBitrate: fromBR,
                                toBitrate: targetBitrate,
                                bufferSeconds: bufferSeconds,
                                reason: reason)
            switchCount += 1
            currentTarget = targetBitrate
            apply(targetBitrate, to: playerItem)
            ABRLogger.switching.info("\(log.displayString, privacy: .public)")
            onSwitch?(log)
        }
    }

    // MARK: - MPC 决策

    /// segment 边界判定：距上次 rollout 是否已推进满一个 segment。
    /// 播放时间倒退（seek）时重置，避免长时间不重算。
    public func shouldRecomputeRollout(at now: Double) -> Bool {
        guard now.isFinite else { return true }
        guard let last = lastRolloutTime else {
            lastRolloutTime = now
            return true
        }
        if now < last {
            lastRolloutTime = now
            return true
        }
        if now - last >= config.mpcDt {
            lastRolloutTime = now
            return true
        }
        return false
    }

    /// MPC 核心决策：安全兜底 + 滚动时域优化
    ///
    /// - Parameter recomputeRollout: 是否重算 rollout。false 时保持上次的目标码率
    ///   （安全兜底仍然生效）。这让"安全反应快、优化决策稳"两件事互不干扰。
    public func decide(bufferSeconds: Double,
                       estimatedThroughput: Double,
                       currentBitrate: Double,
                       recomputeRollout: Bool = true) -> Double {
        let minBR = variants.first!.peakBitRate
        let maxBR = variants.last!.peakBitRate

        // 安全兜底（与 BBA 一致，不可妥协）。每个控制周期都检查，不等 segment 边界。
        if simulateWeakNetwork { return minBR }
        if bufferSeconds < config.reservoir { return minBR }
        if estimatedThroughput <= 0 { return minBR }

        // 未到 segment 边界：维持当前档位，不重算
        if !recomputeRollout, let held = currentTarget {
            return held
        }

        // MPC：对每个候选档位做时域展开，取代价最小者
        var bestBitrate = minBR
        var bestCost = Double.infinity
        for variant in variants {
            let candidate = variant.peakBitRate
            let cost = rolloutCost(candidate: candidate,
                                   currentBitrate: currentBitrate,
                                   buffer: bufferSeconds,
                                   throughput: estimatedThroughput,
                                   maxBR: maxBR)
            if cost < bestCost {
                bestCost = cost
                bestBitrate = candidate
            }
        }
        cumulativeCost += bestCost
        return bestBitrate
    }

    /// 对单个候选档位做"保持该档位"的时域展开，返回总代价
    public func rolloutCost(candidate: Double,
                             currentBitrate: Double,
                             buffer: Double,
                             throughput: Double,
                             maxBR: Double) -> Double {
        var buf = buffer
        var stallSeconds = 0.0
        var cost = 0.0
        let dt = config.mpcDt
        let horizon = config.horizon

        if candidate != currentBitrate {
            cost += config.wSwitch
        }

        for _ in 0..<horizon {
            let drainRate = throughput / candidate
            let next = buf + dt * (drainRate - 1.0)
            if next < 0 {
                // 中途见底：按线性插值折算实际卡顿秒数，惩罚量纲不依赖 dt
                stallSeconds += -next
                buf = 0
            } else {
                buf = next
            }
            cost += config.wQuality * dt * (maxBR - candidate) / maxBR
        }
        cost += config.wStall * stallSeconds
        return cost
    }

    // MARK: - 应用到 AVPlayer

    public func apply(_ targetBitrate: Double, to playerItem: AVPlayerItem) {
        if targetBitrate >= variants.last!.peakBitRate {
            playerItem.preferredPeakBitRate = -1
        } else {
            playerItem.preferredPeakBitRate = targetBitrate
        }
    }

    // MARK: - 辅助

    public func computeBufferSeconds(from item: AVPlayerItem) -> Double {
        let duration = item.duration.seconds
        guard duration.isFinite else { return 0 }
        let currentTime = item.currentTime().seconds
        guard let lastRange = item.loadedTimeRanges.last else { return 0 }
        let loadedEnd = lastRange.timeRangeValue.end.seconds
        return max(0, loadedEnd - currentTime)
    }

    public func observedBitrate(from item: AVPlayerItem) -> Double {
        guard let events = item.accessLog()?.events, let last = events.last else { return 0 }
        return last.observedBitrate
    }

    public func switchReason(bufferSeconds: Double,
                             from: Double, to: Double,
                             throughput: Double) -> String {
        if simulateWeakNetwork { return "MPC 弱网兜底" }
        if bufferSeconds < config.reservoir { return "MPC buffer<reservoir 兜底" }
        if throughput <= 0 { return "MPC 无吞吐观测兜底" }
        if to < from { return "MPC 预测降档(吞吐不足)" }
        if to > from { return "MPC 预测升档(吞吐充足)" }
        return "MPC 保持"
    }
}
