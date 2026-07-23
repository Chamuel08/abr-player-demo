//
//  MPCController.swift
//  ABRPlayerDemo
//
//  SPDD-generated: MPC（Model Predictive Control）ABR 控制器
//
//  在 BBA 安全兜底之上，用滚动时域优化选择目标码率：
//    - 预测模型：buffer(t+1) = buffer(t) + dt * (throughput/bitrate - 1)
//    - 代价函数：J = Σ [ w_stall*stall + w_quality*(max-br)/max ] + w_switch*switch
//    - 求解：对每个候选档位做"保持该档位"的时域展开，取总代价最小者
//    - 安全：buffer < reservoir / 弱网 / 无吞吐观测 时强制最低档（与 BBA 一致）
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

    /// 预测步长（秒）
    let dt: Double = 0.5
    /// 预测时域步数（H=10 → 5 秒）
    let horizon: Int = 10
    /// 代价权重
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
        let targetBitrate = decide(bufferSeconds: bufferSeconds,
                                   estimatedThroughput: estimatedThroughput,
                                   currentBitrate: currentBR)

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

    /// MPC 核心决策：安全兜底 + 滚动时域优化
    func decide(bufferSeconds: Double,
                estimatedThroughput: Double,
                currentBitrate: Double) -> Double {
        let minBR = variants.first!.peakBitRate
        let maxBR = variants.last!.peakBitRate

        // 安全兜底（与 BBA 一致，不可妥协）
        if simulateWeakNetwork { return minBR }
        if bufferSeconds < reservoir { return minBR }
        if estimatedThroughput <= 0 { return minBR }

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
        var stalls = 0
        var cost = 0.0

        // 切档惩罚：候选 ≠ 当前档位时计一次
        if candidate != currentBitrate {
            cost += wSwitch
        }

        for _ in 0..<horizon {
            // buffer 动力学：throughput > bitrate 则涨，反之则跌
            let drainRate = throughput / candidate
            buf += dt * (drainRate - 1.0)
            if buf < 0 {
                stalls += 1
                buf = 0
            }
            // 画质损失（每步累加）：离最高档越远代价越高
            cost += wQuality * (maxBR - candidate) / maxBR
        }
        // 卡顿惩罚
        cost += wStall * Double(stalls)
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
