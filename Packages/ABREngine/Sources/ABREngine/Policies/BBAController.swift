//
//  BBAController.swift
//  ABREngine
//
//  BBA (Buffer-Based Approach) ABR 算法核心
//
//  算法参考 SIGCOM 经典论文，在 AVPlayer 上通过 preferredPeakBitRate 近似实现。
//  参数由 ABRConfig 注入（constitution v2.0 §6），默认值与原硬编码常量一致。
//

import AVFoundation
import Foundation

/// BBA (Buffer-Based Approach) ABR 控制器
///
/// 每 `config.controlLoopInterval` 秒检查一次 buffer 水位，按 BBA 公式计算目标码率，
/// 通过设置 `AVPlayerItem.preferredPeakBitRate` 转向 AVPlayer 选档。
public final class BBAController: ABRController {

    // MARK: - 参数（由 ABRConfig 注入）

    public let config: ABRConfig

    // MARK: - 依赖

    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?
    public private(set) var variants: [HLSVariant]

    // MARK: - 状态

    /// 当前目标码率（bps），nil 表示尚未决策
    public private(set) var currentTarget: Double?
    /// 切档次数
    public private(set) var switchCount: Int = 0
    /// 模拟弱网模式：开启后强制最低档
    public var simulateWeakNetwork: Bool = false

    // MARK: - 回调

    /// 切档回调，UI 订阅用
    public var onSwitch: ((SwitchLog) -> Void)?

    // MARK: - Timer

    private var controlTimer: Timer?

    // MARK: - Init

    public init(player: AVPlayer, variants: [HLSVariant], config: ABRConfig = ABRConfig()) {
        self.player = player
        self.variants = variants.sorted { $0.peakBitRate < $1.peakBitRate }
        self.playerItem = player.currentItem
        self.config = config
    }

    deinit {
        stop()
    }

    // MARK: - 启停

    /// 启动 BBA 控制循环
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

    /// 停止控制循环
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
        let targetBitrate = decide(bufferSeconds: bufferSeconds)

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
            if targetBitrate >= variants.last!.peakBitRate {
                playerItem.preferredPeakBitRate = -1
            } else {
                playerItem.preferredPeakBitRate = targetBitrate
            }
            ABRLogger.switching.info("\(log.displayString, privacy: .public)")
            onSwitch?(log)
        }
    }

    // MARK: - BBA 决策

    /// BBA 核心决策函数
    /// - Parameter bufferSeconds: 当前 buffer 水位（秒）
    /// - Returns: 目标码率（bps）
    public func decide(bufferSeconds: Double) -> Double {
        let sorted = variants
        let minBR = sorted.first!.peakBitRate
        let maxBR = sorted.last!.peakBitRate

        if simulateWeakNetwork {
            return minBR
        }

        let target: Double
        if bufferSeconds < config.reservoir {
            target = minBR
        } else if bufferSeconds > config.reservoir + config.cushion {
            target = maxBR
        } else {
            let ratio = (bufferSeconds - config.reservoir) / config.cushion
            let raw = minBR + ratio * (maxBR - minBR)
            target = quantize(raw, variants: sorted, hysteresis: config.hysteresis,
                              currentTarget: currentTarget)
        }
        return target
    }

    /// 滞回量化：把连续码率量化到最近档位，并应用滞回避免频繁切档
    /// - 升档保守：新档位 > 当前档位时，需要 buffer 超过"目标档位阈值 / hysteresis"才切
    /// - 降档激进：新档位 < 当前档位时，buffer 低于"目标档位阈值 * hysteresis"就切
    public func quantize(_ raw: Double, variants: [HLSVariant],
                         hysteresis: Double, currentTarget: Double?) -> Double {
        var candidateIndex = 0
        for (i, v) in variants.enumerated() {
            if v.peakBitRate >= raw {
                candidateIndex = i
                break
            }
            candidateIndex = i
        }

        if let current = currentTarget,
           variants.contains(where: { $0.peakBitRate == current }) {
            let candidate = variants[candidateIndex].peakBitRate
            if candidate > current {
                if raw < candidate * hysteresis {
                    return current
                }
            } else if candidate < current {
                if raw > candidate / hysteresis {
                    return current
                }
            }
        }
        return variants[candidateIndex].peakBitRate
    }

    // MARK: - 辅助

    /// 从 loadedTimeRanges 计算 buffer 水位（秒）
    public func computeBufferSeconds(from item: AVPlayerItem) -> Double {
        let duration = item.duration.seconds
        guard duration.isFinite else { return 0 }
        let currentTime = item.currentTime().seconds
        guard let lastRange = item.loadedTimeRanges.last else { return 0 }
        let loadedEnd = lastRange.timeRangeValue.end.seconds
        let buffer = max(0, loadedEnd - currentTime)
        return buffer
    }

    /// 生成切档原因字符串
    public func switchReason(bufferSeconds: Double, from: Double, to: Double) -> String {
        if simulateWeakNetwork { return "弱网模拟" }
        if to < from {
            if bufferSeconds < config.reservoir {
                return "buffer<reservoir 降档保安全"
            }
            return "buffer下降 降档"
        } else if to > from {
            if bufferSeconds > config.reservoir + config.cushion {
                return "buffer>\(Int(config.reservoir + config.cushion))s 冲最高档"
            }
            return "buffer充足 升档"
        }
        return "未知"
    }
}
