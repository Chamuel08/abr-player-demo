//
//  StreamLibrary.swift
//  ABRPlayerDemo
//
//  内置 HLS 测试流列表 + SwiftData 持久化的最近播放。
//  见 spec.md FR-6。
//

import Foundation
import SwiftData

/// 一个可播放的 HLS 流
struct StreamItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
    let isBuiltin: Bool
}

/// 内置 HLS 测试流库
enum StreamLibrary {
    /// 内置流（不可删除）
    static let builtin: [StreamItem] = [
        StreamItem(id: "bipbop_4x3", title: "Apple BipBop 4x3 (多码率)",
                   url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")!,
                   isBuiltin: true),
        StreamItem(id: "bipbop_16x9", title: "Apple BipBop 16x9 (多码率)",
                   url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!,
                   isBuiltin: true),
        StreamItem(id: "apple_advanced", title: "Apple Advanced HLS (fMP4)",
                   url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!,
                   isBuiltin: true),
        StreamItem(id: "mux_x36xhzz", title: "Mux x36xhzz (5 档)",
                   url: URL(string: "https://stream.mux.com/v69RSHhFelSm4701snP22dYz2jICy4E4FUyk02rW4gxRM.m3u8")!,
                   isBuiltin: true),
        StreamItem(id: "tubi_test", title: "Tubi Test Stream",
                   url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                   isBuiltin: true),
    ]

    /// 合并内置流与最近播放（去重，内置流优先）
    static func combined(with recents: [PlaybackHistoryItem]) -> [StreamItem] {
        var seen = Set<String>()
        var out: [StreamItem] = []
        for b in builtin {
            out.append(b)
            seen.insert(b.url.absoluteString)
        }
        for r in recents.sorted(by: { $0.lastPlayedAt > $1.lastPlayedAt }) {
            if !seen.contains(r.url.absoluteString) {
                out.append(StreamItem(id: r.url.absoluteString, title: r.title,
                                      url: r.url, isBuiltin: false))
                seen.insert(r.url.absoluteString)
            }
        }
        return out
    }
}
