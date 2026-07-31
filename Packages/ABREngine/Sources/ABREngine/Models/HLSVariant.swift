//
//  HLSVariant.swift
//  ABREngine
//
//  HLS variant（码率档位）数据模型
//

import Foundation

/// 表示 HLS master playlist 中的一个码率档位
public struct HLSVariant: Equatable, Identifiable, Sendable {
    public let id: UUID
    /// 该档位的峰值码率（bps）
    public let peakBitRate: Double
    /// 该档位的子 playlist URL
    public let url: URL

    public init(peakBitRate: Double, url: URL) {
        self.id = UUID()
        self.peakBitRate = peakBitRate
        self.url = url
    }

    /// 便于日志显示的 kbps 字符串
    public var kbpsString: String {
        String(format: "%.0f kbps", peakBitRate / 1000.0)
    }
}

/// 档位解析错误
public enum HLSVariantParserError: Error, LocalizedError {
    case noVariants
    case loadFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .noVariants:
            return "HLS 流没有可用的码率档位"
        case .loadFailed(let underlying):
            return "HLS 档位加载失败: \(underlying.localizedDescription)"
        }
    }
}
