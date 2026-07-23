//
//  ThroughputEstimator.swift
//  ABRPlayerDemo
//
//  SPDD-generated: EWMA 吞吐预测（roadmap 阶段一）
//

import Foundation

/// 指数加权移动平均（EWMA）吞吐估计器
///
/// 用 `throughput_ema = α * current + (1-α) * ema` 平滑观测吞吐，
/// 对网络抖动有一定滤波作用，作为 MPC 的状态输入与独立 QoS 指标。
struct ThroughputEstimator {
    /// 平滑系数，越大越偏向最新观测
    let alpha: Double
    /// 当前 EWMA 估计（bps），无观测时为 0
    private(set) var current: Double = 0

    init(alpha: Double = 0.3) {
        self.alpha = alpha
    }

    /// 喂入一次观测吞吐（bps），返回更新后的 EWMA
    mutating func feed(observed: Double) -> Double {
        guard observed > 0 else { return current }
        if current <= 0 {
            // 首次观测直接采用，避免从 0 缓慢爬升
            current = observed
        } else {
            current = alpha * observed + (1 - alpha) * current
        }
        return current
    }

    /// 重置（切换源或策略时调用）
    mutating func reset() {
        current = 0
    }
}
