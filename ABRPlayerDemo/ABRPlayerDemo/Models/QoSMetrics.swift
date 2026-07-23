//
//  QoSMetrics.swift
//  ABRPlayerDemo
//
//  SPDD-generated: QoS 指标数据模型（对应 constitution §4 的 7 项指标）
//

import Foundation

/// QoS 实时指标，对应 constitution §4 必须显示的 7 项指标
struct QoSMetrics: Equatable {
    /// 当前码率（kbps），来自 accessLog.indicatedBitrate
    var currentBitrate: Double = 0
    /// 观测吞吐（kbps），来自 accessLog.observedBitrate
    var observedBitrate: Double = 0
    /// Buffer 水位（秒），来自 loadedTimeRanges
    var bufferSeconds: Double = 0
    /// 首帧耗时（ms），从 play() 到 timeControlStatus==.playing
    var firstFrameMs: Double = 0
    /// 切档次数，BBAController 内部计数
    var switchCount: Int = 0
    /// 卡顿次数，timeControlStatus==.waitingToPlay 且 reason==.toMinimizeStalls
    var stallCount: Int = 0
    /// 当前档位，BBA 选择的 variant
    var currentVariant: HLSVariant?

    /// 格式化字符串，供 UI 显示
    var currentBitrateString: String {
        currentBitrate > 0 ? String(format: "%.0f kbps", currentBitrate / 1000.0) : "--"
    }
    var observedBitrateString: String {
        observedBitrate > 0 ? String(format: "%.0f kbps", observedBitrate / 1000.0) : "--"
    }
    var bufferString: String {
        String(format: "%.1f s", bufferSeconds)
    }
    var firstFrameString: String {
        firstFrameMs > 0 ? String(format: "%.0f ms", firstFrameMs) : "--"
    }
    var currentVariantString: String {
        currentVariant?.kbpsString ?? "--"
    }
}
