//
//  SwitchLog.swift
//  ABRPlayerDemo
//
//  SPDD-generated: 切档日志数据模型
//

import Foundation

/// 一次切档决策的完整记录（对应 constitution §3）
struct SwitchLog: Identifiable, Equatable {
    let id = UUID()
    /// 决策时间戳
    let timestamp: Date
    /// 切档前码率（bps）
    let fromBitrate: Double
    /// 切档后码率（bps）
    let toBitrate: Double
    /// 决策时的 buffer 水位（秒）
    let bufferSeconds: Double
    /// 切档原因
    let reason: String

    /// 格式化显示字符串
    var displayString: String {
        let timeStr = DateFormatter.logFormatter.string(from: timestamp)
        let from = String(format: "%.0f", fromBitrate / 1000.0)
        let to = String(format: "%.0f", toBitrate / 1000.0)
        let buf = String(format: "%.1f", bufferSeconds)
        return "[\(timeStr)] \(from)kbps → \(to)kbps (buf: \(buf)s, \(reason))"
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
