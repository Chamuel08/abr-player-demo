//
//  MPCController.swift
//  ABRPlayerDemo
//
//  SPDD-generated: MPC（Model Predictive Control）ABR 控制器
//
//  在 BBA 安全兜底之上，用滚动时域优化选择目标码率：
//    - 预测模型：buffer(t+1) = buffer(t) + dt * (throughput/bitrate - 1)
//    - 代价函数：J = Σ [ w_stall*stallSeconds + w_quality*(max-br)/max ] + w_switch*switch
//    - 求解：对每个候选档位做"保持该档位"的时域展开，取总代价最小者
//    - 安全：buffer < reservoir / 弱网 / 无吞吐观测 时强制最低档（与 BBA 一致）
//
//  时域粒度（对齐 FastMPC/RobustMPC, Yin et al. SIGCOMM '15）：
//  预测按 segment 推进（dt = segmentDuration = 4s，horizon = 5 → 20s 窗口），
//  而非按控制周期推进。这一点是必要的：rollout 里的卡顿项只在 buffer 跌破 0 时
//  才计入，若 horizon*dt ≈ reservoir，推演到时域末尾 buffer 还没见底，卡顿项恒为 0，
//  MPC 就看不见卡顿风险、只会一味冲画质。预测窗口必须显著大于 reservoir。
//
//  决策节奏与安全兜底解耦：安全兜底仍按 controlLoopInterval(0.5s) 检查，保证
//  buffer 跌破 reservoir 时能立刻降档；rollout 优化只在 segment 边界重算，
//  避免比 AVPlayer 的实际换档粒度更频繁地抖动目标码率。
//

import AVFoundation
import Foundation

/// MPC（Model Predictive Control）ABR 控制器
final class MPCController: ABRController {

    // MARK: - 常量（与 BBA 对齐，constitution §3）

    let reservoir: Double = 5.0
    let cushion: Double = 10.0
    let hysteresis: Double = 0.8
    let controlLoopInterval: TimeInterval = 0.5

    // MARK: - MPC 参数

    /// segment 时长（秒），预测步长即等于它
    let segmentDuration: Double = 4.0
    /// 预测步长（秒）= 一个 segment
    var dt: Double { segmentDuration }
    /// 预测时域步数（H=5 → 20 秒窗口，必须 >> reservoir）
    let horizon: Int = 5
    /// 代价权重。wStall / wQuality 均按"每秒"计，与 dt 取值解耦：
    /// 改 dt 或 horizon 不会意外改变卡顿与画质的相对权重。
    let wStall: Double = 100
    let wQuality: Double = 10
    let wSwitch: Double = 5

    // MARK: - ABRController 协议

    private(set) var variants: [HLSVariant]
    private(set) var currentTarget: Double?
    private(set) var switchCount: Int = 0
    var simulateWeakNetwork: Bool = false
    var onSwitch: ((SwitchLog) -> Void)?

    // MARK: - MPC 状态

    /// EWMA 吞吐估计（bps）
    private var throughputEstimator = ThroughputEstimator(alpha: 0.3)
    /// 当前 EWMA 吞吐（bps），供 UI 读取
    private(set) var estimatedThroughput: Double = 0
    /// 累计代价 J，供 UI 读取
    private(set) var cumulativeCost: Double = 0
    /// 上次 rollout 重算的时刻（播放时间轴，秒）。nil 表示还没算过。
    private var lastRolloutTime: Double?

    // MARK: - 依赖

    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?
    private var controlTimer: Timer?

    // MARK: - Init

    init(player: AVPlayer, variants: [HLSVariant]) {
        self.player = player
        self.playerItem = player.currentItem
        self.variants = variants.sorted { $0.peakBitRate < $1.peakBitRate }
    }

    deinit {
        stop()
    }

    // MARK: - 启停

    func start() {
        guard controlTimer == nil else { return }
        controlLoop()
        let timer = Timer(timeInterval: controlLoopInterval, repeats: true) { [weak self] _ in
            self?.controlLoop()
        }
        RunLoop.main.add(timer, forMode: .common)
        controlTimer = timer
    }

    func stop() {
        controlTimer?.invalidate()
        controlTimer = nil
    }

    // MARK: - 控制循环

    func controlLoop() {
        guard let playerItem = playerItem ?? player?.currentItem else { return }
        guard !variants.isEmpty else { return }

        let bufferSeconds = computeBufferSeconds(from: playerItem)
        let observed = observedBitrate(from: playerItem)
        if observed > 0 {
            estimatedThroughput = throughputEstimator.feed(observed: observed)
        }

        let currentBR = currentTarget ?? variants.first!.peakBitRate
        // rollout 只在 segment 边界重算；安全兜底每个控制周期都查（见 decide 注释）
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
            onSwitch?(log)
        }
    }

    // MARK: - MPC 决策

    /// segment 边界判定：距上次 rollout 是否已推进满一个 segment。
    /// 播放时间倒退（seek）时重置，避免长时间不重算。
    private func shouldRecomputeRollout(at now: Double) -> Bool {
        guard now.isFinite else { return true }
        guard let last = lastRolloutTime else {
            lastRolloutTime = now
            return true
        }
        if now < last {           // seek 回退
            lastRolloutTime = now
            return true
        }
        if now - last >= segmentDuration {
            lastRolloutTime = now
            return true
        }
        return false
    }

    /// MPC 核心决策：安全兜底 + 滚动时域优化
    ///
    /// - Parameter recomputeRollout: 是否重算 rollout。false 时保持上次的目标码率
    ///   （安全兜底仍然生效）。这让"安全反应快、优化决策稳"两件事互不干扰。
    func decide(bufferSeconds: Double,
                estimatedThroughput: Double,
                currentBitrate: Double,
                recomputeRollout: Bool = true) -> Double {
        let minBR = variants.first!.peakBitRate
        let maxBR = variants.last!.peakBitRate

        // 安全兜底（与 BBA 一致，不可妥协）。每个控制周期都检查，不等 segment 边界。
        if simulateWeakNetwork { return minBR }
        if bufferSeconds < reservoir { return minBR }
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
    private func rolloutCost(candidate: Double,
                             currentBitrate: Double,
                             buffer: Double,
                             throughput: Double,
                             maxBR: Double) -> Double {
        var buf = buffer
        var stallSeconds = 0.0
        var cost = 0.0

        // 切档惩罚：候选 ≠ 当前档位时计一次
        if candidate != currentBitrate {
            cost += wSwitch
        }

        for _ in 0..<horizon {
            // buffer 动力学：throughput > bitrate 则涨，反之则跌
            let drainRate = throughput / candidate
            let next = buf + dt * (drainRate - 1.0)
            if next < 0 {
                // 这一步中途见底。按线性插值折算实际卡顿秒数，
                // 而不是"记一次卡顿"——后者会让惩罚量纲依赖 dt 的取值。
                stallSeconds += -next
                buf = 0
            } else {
                buf = next
            }
            // 画质损失：按秒累加，离最高档越远代价越高
            cost += wQuality * dt * (maxBR - candidate) / maxBR
        }
        // 卡顿惩罚：按秒计
        cost += wStall * stallSeconds
        return cost
    }

    // MARK: - 应用到 AVPlayer

    private func apply(_ targetBitrate: Double, to playerItem: AVPlayerItem) {
        if targetBitrate >= variants.last!.peakBitRate {
            playerItem.preferredPeakBitRate = -1 // 不限制，让 AVPlayer 选最高
        } else {
            playerItem.preferredPeakBitRate = targetBitrate
        }
    }

    // MARK: - 辅助

    private func computeBufferSeconds(from item: AVPlayerItem) -> Double {
        let duration = item.duration.seconds
        guard duration.isFinite else { return 0 }
        let currentTime = item.currentTime().seconds
        guard let lastRange = item.loadedTimeRanges.last else { return 0 }
        let loadedEnd = lastRange.timeRangeValue.end.seconds
        return max(0, loadedEnd - currentTime)
    }

    private func observedBitrate(from item: AVPlayerItem) -> Double {
        guard let events = item.accessLog()?.events, let last = events.last else { return 0 }
        return last.observedBitrate
    }

    private func switchReason(bufferSeconds: Double,
                              from: Double, to: Double,
                              throughput: Double) -> String {
        if simulateWeakNetwork { return "MPC 弱网兜底" }
        if bufferSeconds < reservoir { return "MPC buffer<reservoir 兜底" }
        if throughput <= 0 { return "MPC 无吞吐观测兜底" }
        if to < from { return "MPC 预测降档(吞吐不足)" }
        if to > from { return "MPC 预测升档(吞吐充足)" }
        return "MPC 保持"
    }
}
