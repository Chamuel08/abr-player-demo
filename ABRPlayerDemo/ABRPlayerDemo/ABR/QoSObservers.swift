//
//  QoSObservers.swift
//  ABRPlayerDemo
//
//  SPDD-generated: QoS 指标观察器（KVO + NotificationCenter）
//
//  观察项对应 constitution §4：
//    - loadedTimeRanges KVO → buffer 水位
//    - timeControlStatus KVO → 卡顿检测 + 首帧计时
//    - AVPlayerItemNewAccessLogEntry → 当前码率/观测吞吐
//

import AVFoundation
import Foundation

/// QoS 指标观察器，通过 KVO 和 NotificationCenter 观察 AVPlayer 状态
final class QoSObservers {

    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?

    // MARK: - 观察者

    private var timeControlStatusObs: NSKeyValueObservation?
    private var loadedTimeRangesObs: NSKeyValueObservation?
    private var accessLogObs: NSObjectProtocol?

    // MARK: - 首帧计时

    private var playStartTimestamp: Date?
    private var firstFrameRecorded = false

    // MARK: - 卡顿计数

    private var wasWaitingToPlay = false
    private var stallCount: Int = 0

    // MARK: - 回调

    /// 指标更新回调，UI 订阅用
    var onMetricsUpdate: ((QoSMetrics) -> Void)?
    /// 当前 metrics（内部维护）
    private(set) var metrics = QoSMetrics()

    // MARK: - Init

    init(player: AVPlayer, playStartTimestamp: Date? = nil) {
        self.player = player
        self.playerItem = player.currentItem
        // 支持外部注入 play 开始时间（用于首帧计时，因为观察器可能在 play() 之后才创建）
        if let ts = playStartTimestamp {
            self.playStartTimestamp = ts
        }
    }

    deinit {
        stopObserving()
    }

    // MARK: - 启停

    /// 开始观察
    func startObserving() {
        guard let player = player, let playerItem = playerItem else { return }

        // 1. timeControlStatus KVO → 卡顿检测 + 首帧计时
        timeControlStatusObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.handleTimeControlStatusChange(player.timeControlStatus, reason: player.reasonForWaitingToPlay)
            }
        }

        // 2. loadedTimeRanges KVO → buffer 水位
        loadedTimeRangesObs = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateBufferSeconds(from: item)
            }
        }

        // 3. accessLog 通知 → 当前码率/观测吞吐
        accessLogObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.updateAccessLogMetrics(from: self.playerItem)
        }
    }

    /// 停止观察，清理所有观察者
    func stopObserving() {
        timeControlStatusObs?.invalidate()
        timeControlStatusObs = nil
        loadedTimeRangesObs?.invalidate()
        loadedTimeRangesObs = nil
        if let obs = accessLogObs {
            NotificationCenter.default.removeObserver(obs)
            accessLogObs = nil
        }
    }

    /// 标记 play() 调用时刻，用于首帧计时
    func markPlayStart() {
        playStartTimestamp = Date()
        firstFrameRecorded = false
    }

    // MARK: - 处理

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?) {
        switch status {
        case .playing:
            // 首帧计时
            if !firstFrameRecorded, let start = playStartTimestamp {
                let elapsed = Date().timeIntervalSince(start) * 1000
                metrics.firstFrameMs = elapsed
                firstFrameRecorded = true
                emitMetrics()
            }
            wasWaitingToPlay = false
        case .waitingToPlayAtSpecifiedRate:
            // 卡顿检测：reason == .toMinimizeStalls 表示在等缓冲（真卡顿）
            if reason == .toMinimizeStalls, !wasWaitingToPlay {
                stallCount += 1
                metrics.stallCount = stallCount
                wasWaitingToPlay = true
                emitMetrics()
            }
        case .paused:
            wasWaitingToPlay = false
        @unknown default:
            break
        }
    }

    private func updateBufferSeconds(from item: AVPlayerItem) {
        guard let lastRange = item.loadedTimeRanges.last else {
            metrics.bufferSeconds = 0
            emitMetrics()
            return
        }
        let loadedEnd = lastRange.timeRangeValue.end.seconds
        let currentTime = item.currentTime().seconds
        let buffer = max(0, loadedEnd - currentTime)
        metrics.bufferSeconds = buffer
        emitMetrics()
    }

    private func updateAccessLogMetrics(from item: AVPlayerItem?) {
        guard let item = item,
              let events = item.accessLog()?.events,
              let last = events.last else { return }
        metrics.currentBitrate = last.indicatedBitrate
        metrics.observedBitrate = last.observedBitrate
        emitMetrics()
    }

    private func emitMetrics() {
        onMetricsUpdate?(metrics)
    }
}
