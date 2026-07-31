//
//  HLSVariantParser.swift
//  ABREngine
//
//  解析 HLS master playlist 获取码率档位列表
//

import AVFoundation
import Foundation

/// 解析 HLS master playlist，获取按 peakBitRate 升序排序的档位列表
public enum HLSVariantParser {
    /// 异步解析 AVURLAsset 的可用码率档位
    /// - Parameter asset: 已加载的 AVURLAsset
    /// - Returns: 按 peakBitRate 升序排序的档位列表
    public static func parse(from asset: AVURLAsset) async throws -> [HLSVariant] {
        do {
            let variants = try await asset.load(.variants)
            guard !variants.isEmpty else {
                throw HLSVariantParserError.noVariants
            }

            let result: [HLSVariant] = variants.compactMap { variant -> HLSVariant? in
                guard let peakBitRate = variant.peakBitRate else {
                    return nil
                }
                let url = asset.url
                return HLSVariant(peakBitRate: peakBitRate, url: url)
            }

            guard !result.isEmpty else {
                throw HLSVariantParserError.noVariants
            }

            return result.sorted { $0.peakBitRate < $1.peakBitRate }
        } catch let error as HLSVariantParserError {
            throw error
        } catch {
            throw HLSVariantParserError.loadFailed(underlying: error)
        }
    }
}
