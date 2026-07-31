//
//  PlaybackHistoryItem.swift
//  ABRPlayerDemo
//
//  SwiftData 模型：播放历史。见 spec.md FR-8。
//

import Foundation
import SwiftData

/// 一条播放历史记录（最近播放）
@Model
final class PlaybackHistoryItem {
    /// 流的 URL（作为业务主键）
    var url: URL
    /// 显示标题
    var title: String
    /// 上次播放位置（秒）
    var lastPosition: Double
    /// 上次播放时间
    var lastPlayedAt: Date

    init(url: URL, title: String, lastPosition: Double = 0, lastPlayedAt: Date = .now) {
        self.url = url
        self.title = title
        self.lastPosition = lastPosition
        self.lastPlayedAt = lastPlayedAt
    }
}
