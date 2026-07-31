//
//  SwitchLog.swift
//  ABREngine
//
//  切档日志数据模型
//

import Foundation

/// 一次切档决策的完整记录（对应 constitution §3）
public struct SwitchLog: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 决策时间戳
    public let timestamp: Date
    /// 切档前码率（bps）
    public let fromBitrate: Double
    /// 切档后码率（bps）
    public let toBitrate: Double
    /// 决策时的 buffer 水位（秒）
    public let bufferSeconds: Double
    /// 切档原因
    public let reason: String

    public init(timestamp: Date, fromBitrate: Double, toBitrate: Double,
                bufferSeconds: Double, reason: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.fromBitrate = fromBitrate
        self.toBitrate = toBitrate
        self.bufferSeconds = bufferSeconds
        self.reason = reason
    }

    /// 格式化显示字符串
    public var displayString: String {
        let timeStr = DateFormatter.logFormatter.string(from: timestamp)
        let from = String(format: "%.0f", fromBitrate / 1000.0)
        let to = String(format: "%.0f", toBitrate / 1000.0)
        let buf = String(format: "%.1f", bufferSeconds)
        return "[\(timeStr)] \(from)kbps → \(to)kbps (buf: \(buf)s, \(reason))"
    }
}

extension DateFormatter {
    /// 切档日志时间格式（HH:mm:ss）
    public static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
