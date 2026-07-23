//
//  ABRPlayerController.swift
//  ABRPlayerDemo
//
//  SPDD-generated: AVPlayer 封装，SwiftUI 的 ObservableObject，协调各子模块
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

/// ABR 播放器控制器：封装 AVPlayer，作为 SwiftUI 的 ObservableObject
final class ABRPlayerController: ObservableObject {

    // MARK: - Published（UI 订阅）

    /// QoS 实时指标
    @Published private(set) var metrics = QoSMetrics()
    /// 切档日志（保留最近 10 条）
    @Published private(set) var switchLogs: [SwitchLog] = []
    /// 是否在播放
    @Published private(set) var isPlaying = false
    /// 是否已加载档位（BBA 是否就绪）
    @Published private(set) var variantsReady = false
    /// 模拟弱网开关
    @Published var simulateWeakNetwork = false {
        didSet {
            bbaController?.simulateWeakNetwork = simulateWeakNetwork
        }
    }

    /// play() 调用时间戳，用于首帧计时（观察器可能在 play() 之后才创建，需注入）
    private var playStartTime: Date?

    /// 测试钩子：通过环境变量 ABR_WEAK_NETWORK=1 启动可默认开启弱网模式（用于自动化验证降档）
    private static var weakNetworkFromEnv: Bool {
        ProcessInfo.processInfo.environment["ABR_WEAK_NETWORK"] == "1"
    }

    // MARK: - AVPlayer

    /// 暴露给 PlayerView 用
    let player: AVPlayer
    private let url: URL
    private var playerItem: AVPlayerItem

    // MARK: - 子模块

    private var bbaController: BBAController?
    private var qosObservers: QoSObservers?

    // MARK: - Init

    init(url: URL) {
        self.url = url
        let asset = AVURLAsset(url: url)
        self.playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        // 测试钩子：环境变量可默认开启弱网模式
        if Self.weakNetworkFromEnv {
            self.simulateWeakNetwork = true
        }
        // 关闭 AVPlayer 默认 ABR 的部分行为：通过 preferredPeakBitRate 控制
        // 但默认还是要让它先播放，BBA 接管后再限制
    }

    deinit {
        qosObservers?.stopObserving()
        bbaController?.stop()
        player.pause()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 播放控制

    /// 开始播放并启动 BBA + QoS 监控
    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        playStartTime = Date()
        qosObservers?.markPlayStart()
        player.play()

        // 异步加载档位并启动 BBA
        Task { [weak self] in
            guard let self = self else { return }
            await self.setupBBA()
        }
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
    }

    // MARK: - BBA 初始化

    @MainActor
    private func setupBBA() async {
        guard let asset = playerItem.asset as? AVURLAsset else { return }
        do {
            let variants = try await HLSVariantParser.parse(from: asset)
            await MainActor.run {
                self.bbaController = BBAController(player: self.player, variants: variants)
                // 同步弱网开关状态（init 时 didSet 可能因 bbaController 尚未创建而失效）
                self.bbaController?.simulateWeakNetwork = self.simulateWeakNetwork
                self.bbaController?.onSwitch = { [weak self] log in
                    guard let self = self else { return }
                    // 追加日志，保留最近 10 条
                    self.switchLogs.append(log)
                    if self.switchLogs.count > 10 {
                        self.switchLogs.removeFirst(self.switchLogs.count - 10)
                    }
                    // 同步切档次数到 metrics
                    self.metrics.switchCount = self.bbaController?.switchCount ?? 0
                    self.metrics.currentVariant = variants.first(where: {
                        $0.peakBitRate == self.bbaController?.currentTarget
                    })
                }
                self.bbaController?.start()
                self.variantsReady = true
                // 启动 QoS 观察器
                self.qosObservers = QoSObservers(player: self.player, playStartTimestamp: self.playStartTime)
                self.qosObservers?.onMetricsUpdate = { [weak self] newMetrics in
                    guard let self = self else { return }
                    // 保留 BBAController 的切档次数和当前档位
                    var merged = newMetrics
                    merged.switchCount = self.bbaController?.switchCount ?? 0
                    if let target = self.bbaController?.currentTarget {
                        merged.currentVariant = variants.first(where: { $0.peakBitRate == target })
                    }
                    self.metrics = merged
                }
                self.qosObservers?.startObserving()
            }
        } catch {
            print("[BBA] 档位解析失败: \(error.localizedDescription)")
            // 降级：仍启动 QoS 观察器，不启动 BBA
            await MainActor.run {
                self.qosObservers = QoSObservers(player: self.player, playStartTimestamp: self.playStartTime)
                self.qosObservers?.onMetricsUpdate = { [weak self] newMetrics in
                    self?.metrics = newMetrics
                }
                self.qosObservers?.startObserving()
            }
        }
    }
}
