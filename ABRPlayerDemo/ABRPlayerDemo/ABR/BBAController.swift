//
//  BBAController.swift
//  ABRPlayerDemo
//
//  SPDD-generated: BBA (Buffer-Based Approach) ABR 算法核心
//
//  算法参考 SIGCOM 经典论文，在 AVPlayer 上通过 preferredPeakBitRate 近似实现。
//  参数对应 constitution §3：
//    reservoir = 5s   (buffer 低于此值强制最低档，保不卡顿)
//    cushion   = 10s  (buffer 高于 reservoir+cushion=15s 可冲最高档)
//    hysteresis = 0.8 (升档保守、降档激进的滞回系数)
//

import AVFoundation
import Foundation

/// BBA (Buffer-Based Approach) ABR 控制器
///
/// 每 0.5 秒检查一次 buffer 水位，按 BBA 公式计算目标码率，
/// 通过设置 `AVPlayerItem.preferredPeakBitRate` 转向 AVPlayer 选档。
final class BBAController {

    // MARK: - 常量（constitution §3）

    /// reservoir：buffer 低于此值强制最低档（秒）
    let reservoir: Double = 5.0
    /// cushion：buffer 高于 reservoir+cushion 可冲最高档（秒）
    let cushion: Double = 10.0
    /// 滞回系数：升档阈值乘以 1/hysteresis，降档阈值乘以 hysteresis
    let hysteresis: Double = 0.8
    /// 控制循环周期（秒）
    let controlLoopInterval: TimeInterval = 0.5

    // MARK: - 依赖

    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?
    private(set) var variants: [HLSVariant]

    // MARK: - 状态

    /// 当前目标码率（bps），nil 表示尚未决策
    private(set) var currentTarget: Double?
    /// 切档次数
    private(set) var switchCount: Int = 0
    /// 模拟弱网模式：开启后强制最低档
    var simulateWeakNetwork: Bool = false

    // MARK: - 回调

    /// 切档回调，UI 订阅用
    var onSwitch: ((SwitchLog) -> Void)?

    // MARK: - Timer

    private var controlTimer: Timer?

    // MARK: - Init

    init(player: AVPlayer, variants: [HLSVariant]) {
        self.player = player
        self.variants = variants.sorted { $0.peakBitRate < $1.peakBitRate }
        self.playerItem = player.currentItem
    }

    deinit {
        stop()
    }

    // MARK: - 启停

    /// 启动 BBA 控制循环（每 0.5s 一次）
    func start() {
        guard controlTimer == nil else { return }
        // 首次立即执行一次
        controlLoop()
        // 用闭包式 Timer + weak self，避免 target-action 对 NSObject 的依赖
        let timer = Timer(timeInterval: controlLoopInterval, repeats: true) { [weak self] _ in
            self?.controlLoop()
        }
        RunLoop.main.add(timer, forMode: .common)
        controlTimer = timer
    }

    /// 停止控制循环
    func stop() {
        controlTimer?.invalidate()
        controlTimer = nil
    }

    // MARK: - 控制循环

    func controlLoop() {
        guard let playerItem = playerItem ?? player?.currentItem else { return }
        guard !variants.isEmpty else { return }

        let bufferSeconds = computeBufferSeconds(from: playerItem)
        let targetBitrate = decide(bufferSeconds: bufferSeconds)

        // 首次决策或目标变化时切档
        if targetBitrate != currentTarget {
            let fromBR = currentTarget ?? 0
            let reason = switchReason(bufferSeconds: bufferSeconds, from: fromBR, to: targetBitrate)
            let log = SwitchLog(
                timestamp: Date(),
                fromBitrate: fromBR,
                toBitrate: targetBitrate,
                bufferSeconds: bufferSeconds,
                reason: reason
            )
            switchCount += 1
            currentTarget = targetBitrate
            // 设置 preferredPeakBitRate 转向 AVPlayer
            // -1 表示不限制（冲最高档），>0 表示限制到该值
            if targetBitrate >= variants.last!.peakBitRate {
                playerItem.preferredPeakBitRate = -1 // 不限制，让 AVPlayer 选最高
            } else {
                playerItem.preferredPeakBitRate = targetBitrate
            }
            onSwitch?(log)
        }
    }

    // MARK: - BBA 决策

    /// BBA 核心决策函数
    /// - Parameter bufferSeconds: 当前 buffer 水位（秒）
    /// - Returns: 目标码率（bps）
    func decide(bufferSeconds: Double) -> Double {
        let sorted = variants
        let minBR = sorted.first!.peakBitRate
        let maxBR = sorted.last!.peakBitRate

        // 弱网模拟：强制最低档
        if simulateWeakNetwork {
            return minBR
        }

        let target: Double
        if bufferSeconds < reservoir {
            // 安全区：强制最低档
            target = minBR
        } else if bufferSeconds > reservoir + cushion {
            // 加速区：冲最高档
            target = maxBR
        } else {
            // 线性插值区：reservoir <= buffer <= reservoir+cushion
            let ratio = (bufferSeconds - reservoir) / cushion
            let raw = minBR + ratio * (maxBR - minBR)
            target = quantize(raw, variants: sorted, hysteresis: hysteresis,
                              currentTarget: currentTarget)
        }
        return target
    }

    /// 滞回量化：把连续码率量化到最近档位，并应用滞回避免频繁切档
    /// - 升档保守：新档位 > 当前档位时，需要 buffer 超过"目标档位阈值 / hysteresis"才切
    /// - 降档激进：新档位 < 当前档位时，buffer 低于"目标档位阈值 * hysteresis"就切
    private func quantize(_ raw: Double, variants: [HLSVariant],
                          hysteresis: Double, currentTarget: Double?) -> Double {
        // 找到 raw 对应的最近档位（按码率）
        // 简单实现：选第一个 peakBitRate >= raw 的档位，否则最高档
        var candidateIndex = 0
        for (i, v) in variants.enumerated() {
            if v.peakBitRate >= raw {
                candidateIndex = i
                break
            }
            candidateIndex = i
        }

        // 滞回：如果当前已有目标，且候选档位与当前档位不同，应用滞回
        if let current = currentTarget,
           variants.contains(where: { $0.peakBitRate == current }) {
            let candidate = variants[candidateIndex].peakBitRate
            if candidate > current {
                // 升档：需要候选档位的"门槛"更高，乘以 1/hysteresis
                // 这里简化：如果 raw 没有超过候选档位 * hysteresis，保持当前档
                if raw < candidate * hysteresis {
                    return current
                }
            } else if candidate < current {
                // 降档：如果 raw 没有低于候选档位 / hysteresis，保持当前档
                if raw > candidate / hysteresis {
                    return current
                }
            }
        }
        return variants[candidateIndex].peakBitRate
    }

    // MARK: - 辅助

    /// 从 loadedTimeRanges 计算 buffer 水位（秒）
    private func computeBufferSeconds(from item: AVPlayerItem) -> Double {
        let duration = item.duration.seconds
        guard duration.isFinite else { return 0 }
        let currentTime = item.currentTime().seconds
        guard let lastRange = item.loadedTimeRanges.last else { return 0 }
        let loadedEnd = lastRange.timeRangeValue.end.seconds
        // buffer = 已加载末尾 - 当前播放位置
        let buffer = max(0, loadedEnd - currentTime)
        return buffer
    }

    /// 生成切档原因字符串
    private func switchReason(bufferSeconds: Double, from: Double, to: Double) -> String {
        if simulateWeakNetwork { return "弱网模拟" }
        if to < from {
            if bufferSeconds < reservoir {
                return "buffer<reservoir 降档保安全"
            }
            return "buffer下降 降档"
        } else if to > from {
            if bufferSeconds > reservoir + cushion {
                return "buffer>15s 冲最高档"
            }
            return "buffer充足 升档"
        }
        return "未知"
    }
}
