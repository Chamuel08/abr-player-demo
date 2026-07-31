//
//  QoSMetrics.swift
//  ABREngine
//
//  QoS 指标数据模型（对应 constitution §4 的 7 项指标 + MPC 专属 2 项）
//

import Foundation

/// QoS 实时指标，对应 constitution §4 必须显示的 7 项指标
public struct QoSMetrics: Equatable, Sendable {
    /// 当前码率（bps），来自 accessLog.indicatedBitrate
    public var currentBitrate: Double = 0
    /// 观测吞吐（bps），来自 accessLog.observedBitrate
    public var observedBitrate: Double = 0
    /// Buffer 水位（秒），来自 loadedTimeRanges
    public var bufferSeconds: Double = 0
    /// 首帧耗时（ms），从 play() 到 timeControlStatus==.playing
    public var firstFrameMs: Double = 0
    /// 切档次数，ABRController 内部计数
    public var switchCount: Int = 0
    /// 卡顿次数，timeControlStatus==.waitingToPlay 且 reason==.toMinimizeStalls
    public var stallCount: Int = 0
    /// 当前档位，ABR 选择的 variant
    public var currentVariant: HLSVariant?
    /// EWMA 预测吞吐（bps），MPC 策略下由 MPCController 提供
    public var estimatedThroughput: Double = 0
    /// MPC 累计代价 J，仅 MPC 策略有意义
    public var cumulativeCost: Double = 0

    public init() {}

    /// 格式化字符串，供 UI 显示
    public var currentBitrateString: String {
        currentBitrate > 0 ? String(format: "%.0f kbps", currentBitrate / 1000.0) : "--"
    }
    public var observedBitrateString: String {
        observedBitrate > 0 ? String(format: "%.0f kbps", observedBitrate / 1000.0) : "--"
    }
    public var bufferString: String {
        String(format: "%.1f s", bufferSeconds)
    }
    public var firstFrameString: String {
        firstFrameMs > 0 ? String(format: "%.0f ms", firstFrameMs) : "--"
    }
    public var currentVariantString: String {
        currentVariant?.kbpsString ?? "--"
    }
    public var estimatedThroughputString: String {
        estimatedThroughput > 0 ? String(format: "%.0f kbps", estimatedThroughput / 1000.0) : "--"
    }
    public var cumulativeCostString: String {
        String(format: "%.0f", cumulativeCost)
    }
}
