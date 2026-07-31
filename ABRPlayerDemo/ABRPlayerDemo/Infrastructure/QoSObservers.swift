//
//  QoSObservers.swift
//  ABRPlayerDemo
//
//  QoS 指标观察器（KVO + NotificationCenter）。
//  观察项对应 constitution §4：
//    - loadedTimeRanges KVO → buffer 水位
//    - timeControlStatus KVO → 卡顿检测 + 首帧计时
//    - AVPlayerItemNewAccessLogEntry → 当前码率/观测吞吐
//

import AVFoundation
import Foundation
import ABREngine

/// QoS 指标观察器，通过 KVO 和 NotificationCenter 观察 AVPlayer 状态
final class QoSObservers {

    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?

    private var timeControlStatusObs: NSKeyValueObservation?
    private var loadedTimeRangesObs: NSKeyValueObservation?
    private var accessLogObs: NSObjectProtocol?

    private var playStartTimestamp: Date?
    private var firstFrameRecorded = false

    private var wasWaitingToPlay = false
    private var stallCount: Int = 0

    /// 指标更新回调，UI 订阅用
    var onMetricsUpdate: ((QoSMetrics) -> Void)?
    private(set) var metrics = QoSMetrics()

    init(player: AVPlayer, playStartTimestamp: Date? = nil) {
        self.player = player
        self.playerItem = player.currentItem
        if let ts = playStartTimestamp {
            self.playStartTimestamp = ts
        }
    }

    deinit {
        stopObserving()
    }

    /// 开始观察
    func startObserving() {
        guard let player = player, let playerItem = playerItem else { return }

        timeControlStatusObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.handleTimeControlStatusChange(player.timeControlStatus, reason: player.reasonForWaitingToPlay)
            }
        }

        loadedTimeRangesObs = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateBufferSeconds(from: item)
            }
        }

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

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?) {
        switch status {
        case .playing:
            if !firstFrameRecorded, let start = playStartTimestamp {
                let elapsed = Date().timeIntervalSince(start) * 1000
                metrics.firstFrameMs = elapsed
                firstFrameRecorded = true
                emitMetrics()
            }
            wasWaitingToPlay = false
        case .waitingToPlayAtSpecifiedRate:
            if reason == .toMinimizeStalls, !wasWaitingToPlay {
                stallCount += 1
                metrics.stallCount = stallCount
                wasWaitingToPlay = true
                ABRLogger.stall.warning("stall #\(self.stallCount)")
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
