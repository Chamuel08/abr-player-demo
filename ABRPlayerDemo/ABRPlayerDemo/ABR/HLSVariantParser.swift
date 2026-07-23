//
//  HLSVariantParser.swift
//  ABRPlayerDemo
//
//  SPDD-generated: 解析 HLS master playlist 获取码率档位列表
//

import AVFoundation
import Foundation

/// 解析 HLS master playlist，获取按 peakBitRate 升序排序的档位列表
enum HLSVariantParser {
    /// 异步解析 AVURLAsset 的可用码率档位
    /// - Parameter asset: 已加载的 AVURLAsset
    /// - Returns: 按 peakBitRate 升序排序的档位列表
    static func parse(from asset: AVURLAsset) async throws -> [HLSVariant] {
        do {
            // iOS 15+ 异步加载 variants API
            let variants = try await asset.load(.variants)
            guard !variants.isEmpty else {
                throw HLSVariantParserError.noVariants
            }

            let result: [HLSVariant] = variants.compactMap { variant -> HLSVariant? in
                // AVAssetVariant.peakBitRate 在本 SDK 是 Double?，nil 时跳过该档位
                guard let peakBitRate = variant.peakBitRate else {
                    return nil
                }
                // variant 的 URL：AVAssetVariant 不直接暴露子 playlist URL，用原始 asset URL
                let url = asset.url
                return HLSVariant(peakBitRate: peakBitRate, url: url)
            }

            guard !result.isEmpty else {
                throw HLSVariantParserError.noVariants
            }

            // 按 peakBitRate 升序排序
            return result.sorted { $0.peakBitRate < $1.peakBitRate }
        } catch let error as HLSVariantParserError {
            throw error
        } catch {
            throw HLSVariantParserError.loadFailed(underlying: error)
        }
    }
}
