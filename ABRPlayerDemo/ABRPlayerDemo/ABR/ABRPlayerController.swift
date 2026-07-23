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
            abr?.simulateWeakNetwork = simulateWeakNetwork
        }
    }

    /// ABR 策略
    enum ABRStrategy: String, CaseIterable, Identifiable {
        case bba = "BBA"
        case mpc = "MPC"
        var id: String { rawValue }
    }
    /// 当前策略，切换时重建控制器
    @Published var strategy: ABRStrategy = .bba {
        didSet {
            guard strategy != oldValue else { return }
            rebuildABR()
        }
    }

    /// play() 调用时间戳，用于首帧计时（观察器可能在 play() 之后才创建，需注入）
    private var playStartTime: Date?

    /// 测试钩子：通过环境变量 ABR_WEAK_NETWORK=1 启动可默认开启弱网模式（用于自动化验证降档）
    private static var weakNetworkFromEnv: Bool {
        ProcessInfo.processInfo.environment["ABR_WEAK_NETWORK"] == "1"
    }
    /// 测试钩子：通过环境变量 ABR_STRATEGY=mpc 启动可默认选 MPC（用于自动化验证）
    private static var strategyFromEnv: ABRStrategy {
        ProcessInfo.processInfo.environment["ABR_STRATEGY"]?.lowercased() == "mpc" ? .mpc : .bba
    }

    // MARK: - AVPlayer

    /// 暴露给 PlayerView 用
    let player: AVPlayer
    private let url: URL
    private var playerItem: AVPlayerItem

    // MARK: - 子模块

    private var abr: ABRController?
    private var qosObservers: QoSObservers?
    /// 已解析的档位，切换策略时复用
    private var parsedVariants: [HLSVariant]?

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
        // 测试钩子：环境变量可默认选策略
        self.strategy = Self.strategyFromEnv
        // 关闭 AVPlayer 默认 ABR 的部分行为：通过 preferredPeakBitRate 控制
        // 但默认还是要让它先播放，BBA 接管后再限制
    }

    deinit {
        qosObservers?.stopObserving()
        abr?.stop()
        player.pause()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 播放控制

    /// 开始播放并启动 ABR + QoS 监控
    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        playStartTime = Date()
        qosObservers?.markPlayStart()
        player.play()

        // 异步加载档位并启动 ABR
        Task { [weak self] in
            guard let self = self else { return }
            await self.setupABR()
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

    // MARK: - ABR 初始化

    @MainActor
    private func setupABR() async {
        guard let asset = playerItem.asset as? AVURLAsset else { return }
        do {
            let variants = try await HLSVariantParser.parse(from: asset)
            await MainActor.run {
                self.parsedVariants = variants
                self.installABR(variants: variants)
                self.variantsReady = true
                self.startQoSObservers(variants: variants)
            }
        } catch {
            print("[ABR] 档位解析失败: \(error.localizedDescription)")
            // 降级：仍启动 QoS 观察器，不启动 ABR
            await MainActor.run {
                self.startQoSObservers(variants: [])
            }
        }
    }

    /// 切换策略时重建控制器（不中断播放，复用已解析档位）
    private func rebuildABR() {
        guard isPlaying, let variants = parsedVariants else { return }
        abr?.stop()
        // 切换策略时清空切档日志与计数，便于对比
        switchLogs.removeAll()
        installABR(variants: variants)
    }

    /// 根据 strategy 构造并安装 ABR 控制器
    private func installABR(variants: [HLSVariant]) {
        let controller: ABRController
        switch strategy {
        case .bba:
            controller = BBAController(player: player, variants: variants)
        case .mpc:
            controller = MPCController(player: player, variants: variants)
        }
        controller.simulateWeakNetwork = simulateWeakNetwork
        controller.onSwitch = { [weak self] log in
            guard let self = self else { return }
            self.switchLogs.append(log)
            if self.switchLogs.count > 10 {
                self.switchLogs.removeFirst(self.switchLogs.count - 10)
            }
        }
        controller.start()
        abr = controller
    }

    /// 启动 QoS 观察器，并把 ABR 状态合并进 metrics
    private func startQoSObservers(variants: [HLSVariant]) {
        qosObservers = QoSObservers(player: player, playStartTimestamp: playStartTime)
        qosObservers?.onMetricsUpdate = { [weak self] newMetrics in
            guard let self = self else { return }
            var merged = newMetrics
            merged.switchCount = self.abr?.switchCount ?? 0
            if let target = self.abr?.currentTarget {
                merged.currentVariant = variants.first(where: { $0.peakBitRate == target })
            }
            // MPC 专属指标
            if let mpc = self.abr as? MPCController {
                merged.estimatedThroughput = mpc.estimatedThroughput
                merged.cumulativeCost = mpc.cumulativeCost
            } else {
                merged.estimatedThroughput = 0
                merged.cumulativeCost = 0
            }
            self.metrics = merged
        }
        qosObservers?.startObserving()
    }
}
