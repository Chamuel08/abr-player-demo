//
//  QoSLogEntry.swift
//  ABRPlayerDemo
//
//  SwiftData 模型：QoS 采样日志。每 0.5s 一条（仅调试模式）。
//  见 spec.md FR-8、constitution v2.0 §5。
//

import Foundation
import SwiftData

/// 一条 QoS 采样记录（每 0.5s 写入一条，仅 qosLoggingEnabled 时写入）
@Model
final class QoSLogEntry {
    /// 会话 ID（同一次播放的所有采样共享）
    var sessionID: UUID
    /// 采样时间戳
    var timestamp: Date
    /// 相对播放开始的秒数
    var playbackTime: Double
    /// Buffer 水位（秒）
    var bufferSeconds: Double
    /// 当前码率（bps）
    var currentBitrate: Double
    /// 观测吞吐（bps）
    var observedBitrate: Double
    /// 目标码率（bps，ABR 决策结果）
    var targetBitrate: Double
    /// 累计切档次数
    var switchCount: Int
    /// 累计卡顿次数
    var stallCount: Int

    init(sessionID: UUID, timestamp: Date, playbackTime: Double,
         bufferSeconds: Double, currentBitrate: Double, observedBitrate: Double,
         targetBitrate: Double, switchCount: Int, stallCount: Int) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.playbackTime = playbackTime
        self.bufferSeconds = bufferSeconds
        self.currentBitrate = currentBitrate
        self.observedBitrate = observedBitrate
        self.targetBitrate = targetBitrate
        self.switchCount = switchCount
        self.stallCount = stallCount
    }
}
