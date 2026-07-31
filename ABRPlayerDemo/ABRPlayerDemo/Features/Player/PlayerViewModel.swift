//
//  PlayerViewModel.swift
//  ABRPlayerDemo
//
//  @Observable 播放器视图模型。拆自旧 ABRPlayerController：
//  只管 AVPlayer + ABREngine 的 ABRController + QoS 采样写 SwiftData。
//  见 plan.md §2.2。
//

import AVFoundation
import Foundation
import Observation
import SwiftData
import ABREngine

/// 播放器视图模型（@Observable，iOS 17+）
@Observable
final class PlayerViewModel {
    // MARK: - 对外可观察状态
    var metrics = QoSMetrics()
    var switchLogs: [SwitchLog] = []
    var isPlaying = false
    var variantsReady = false
    var errorMessage: String?

    // MARK: - 依赖
    let stream: StreamItem
    let player: AVPlayer
    private let playerItem: AVPlayerItem
    private let settings: SettingsStore
    private let modelContext: ModelContext?

    // MARK: - ABR / QoS 子模块
    var abr: (any ABRController)?
    private var qosObservers: QoSObservers?
    private var parsedVariants: [HLSVariant]?

    private var qosSampleTimer: Timer?
    private let sessionID = UUID()

    // MARK: - Init
    init(stream: StreamItem, settings: SettingsStore, modelContext: ModelContext?) {
        self.stream = stream
        self.settings = settings
        self.modelContext = modelContext
        let asset = AVURLAsset(url: stream.url)
        self.playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
    }

    deinit {
        stop()
    }

    // MARK: - 播放控制

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        qosObservers?.markPlayStart()
        player.play()
        Task { [weak self] in
            await self?.setupABR()
        }
        startQoSSampling()
    }

    func pause() {
        isPlaying = false
        player.pause()
        stopQoSSampling()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
    }

    func stop() {
        stopQoSSampling()
        qosObservers?.stopObserving()
        abr?.stop()
        player.pause()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - ABR 初始化

    @MainActor
    private func setupABR() async {
        guard let asset = playerItem.asset as? AVURLAsset else { return }
        do {
            let variants = try await HLSVariantParser.parse(from: asset)
            installABR(variants: variants)
            variantsReady = true
            startQoSObservers(variants: variants)
        } catch {
            ABRLogger.error.error("档位解析失败: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            startQoSObservers(variants: [])
        }
    }

    private func installABR(variants: [HLSVariant]) {
        let config = settings.makeConfig()
        let controller: any ABRController
        switch settings.strategy {
        case .bba:
            controller = BBAController(player: player, variants: variants, config: config)
        case .mpc:
            controller = MPCController(player: player, variants: variants, config: config)
        }
        controller.simulateWeakNetwork = settings.weakNetwork
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

    /// 切换策略时重建控制器（不中断播放，复用已解析档位）
    func rebuildABR() {
        guard isPlaying, let variants = parsedVariants else { return }
        abr?.stop()
        switchLogs.removeAll()
        installABR(variants: variants)
    }

    /// 参数变化时重建控制器（保持当前策略，注入新 config）
    func refreshConfig() {
        guard isPlaying, let variants = parsedVariants else { return }
        abr?.stop()
        switchLogs.removeAll()
        installABR(variants: variants)
    }

    private func startQoSObservers(variants: [HLSVariant]) {
        parsedVariants = variants
        qosObservers = QoSObservers(player: player)
        qosObservers?.onMetricsUpdate = { [weak self] newMetrics in
            guard let self = self else { return }
            var merged = newMetrics
            merged.switchCount = self.abr?.switchCount ?? 0
            if let target = self.abr?.currentTarget {
                merged.currentVariant = variants.first(where: { $0.peakBitRate == target })
            }
            if let mpc = self.abr as? MPCController {
                merged.estimatedThroughput = mpc.estimatedThroughput
                merged.cumulativeCost = mpc.cumulativeCost
            }
            self.metrics = merged
        }
        qosObservers?.startObserving()
    }

    // MARK: - QoS 采样写 SwiftData

    private func startQoSSampling() {
        guard qosSampleTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.writeQoSSample()
        }
        RunLoop.main.add(timer, forMode: .common)
        qosSampleTimer = timer
    }

    private func stopQoSSampling() {
        qosSampleTimer?.invalidate()
        qosSampleTimer = nil
    }

    private func writeQoSSample() {
        guard settings.qosLoggingEnabled, let modelContext else { return }
        let entry = QoSLogEntry(
            sessionID: sessionID,
            timestamp: .now,
            playbackTime: playerItem.currentTime().seconds,
            bufferSeconds: metrics.bufferSeconds,
            currentBitrate: metrics.currentBitrate,
            observedBitrate: metrics.observedBitrate,
            targetBitrate: abr?.currentTarget ?? 0,
            switchCount: metrics.switchCount,
            stallCount: metrics.stallCount
        )
        modelContext.insert(entry)
        // 自动截断：保留最近 2000 条
        trimQoSLogs()
        try? modelContext.save()
    }

    private func trimQoSLogs() {
        guard let modelContext else { return }
        let maxEntries = 2000
        let fetch = FetchDescriptor<QoSLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? modelContext.fetch(fetch) else { return }
        if all.count > maxEntries {
            for entry in all.dropFirst(maxEntries) {
                modelContext.delete(entry)
            }
        }
    }
}
