//
//  QoSLogExporter.swift
//  ABRPlayerDemo
//
//  从 SwiftData 读 QoSLogEntry，写 CSV 到 tmp，供 ShareLink 导出。
//  见 spec.md FR-12、plan.md §2.2。
//

import Foundation
import SwiftData

/// QoS 日志 CSV 导出器
enum QoSLogExporter {
    /// 导出指定会话的 QoS 采样为 CSV，返回临时文件 URL
    static func export(sessionID: UUID?, from context: ModelContext) throws -> URL {
        var descriptor = FetchDescriptor<QoSLogEntry>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        if let sessionID {
            descriptor.predicate = #Predicate { $0.sessionID == sessionID }
        }
        let entries = try context.fetch(descriptor)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qos_log_\(Date().timeIntervalSince1970).csv")
        var lines = ["timestamp,playback_time,buffer_seconds,current_bitrate,observed_bitrate,target_bitrate,switch_count,stall_count"]
        for e in entries {
            let row = "\(ISO8601DateFormatter().string(from: e.timestamp)),\(e.playbackTime),\(e.bufferSeconds),\(e.currentBitrate),\(e.observedBitrate),\(e.targetBitrate),\(e.switchCount),\(e.stallCount)"
            lines.append(row)
        }
        let csv = lines.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
