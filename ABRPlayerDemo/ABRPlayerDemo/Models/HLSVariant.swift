//
//  HLSVariant.swift
//  ABRPlayerDemo
//
//  SPDD-generated: HLS variant (码率档位) 数据模型
//

import Foundation

/// 表示 HLS master playlist 中的一个码率档位
struct HLSVariant: Equatable, Identifiable {
    let id = UUID()
    /// 该档位的峰值码率（bps）
    let peakBitRate: Double
    /// 该档位的子 playlist URL
    let url: URL

    /// 便于日志显示的 kbps 字符串
    var kbpsString: String {
        String(format: "%.0f kbps", peakBitRate / 1000.0)
    }
}

/// 档位解析错误
enum HLSVariantParserError: Error, LocalizedError {
    case noVariants
    case loadFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noVariants:
            return "HLS 流没有可用的码率档位"
        case .loadFailed(let underlying):
            return "HLS 档位加载失败: \(underlying.localizedDescription)"
        }
    }
}
