//
//  ABRConfig.swift
//  ABREngine
//
//  ABR 算法参数集合。把原本硬编码在各控制器内的 `let reservoir = 5.0` 等常量
//  打包成可注入的 struct，让 Settings 调参与离线搜参结果写回有统一入口。
//  见 constitution v2.0 §6。
//

import Foundation

/// ABR 算法全部可调参数
///
/// 由 `SettingsStore` 构造后注入 `BBAController` / `MPCController`。
/// 默认值与原硬编码常量一致（reservoir=5 / cushion=10 / hysteresis=0.8 等），
/// 改动默认值需同步 `scripts/simulate_abr.py` 的 `DEFAULTS`。
public struct ABRConfig: Equatable, Sendable {
    // MARK: - BBA / MPC 共享 buffer 参数
    /// buffer 低于此值强制最低档（秒）
    public var reservoir: Double
    /// buffer 高于 reservoir+cushion 可冲最高档（秒）
    public var cushion: Double
    /// 滞回系数：升档保守、降档激进
    public var hysteresis: Double

    // MARK: - MPC 代价权重（按秒计，与 dt 解耦）
    /// 每秒卡顿的惩罚
    public var wStall: Double
    /// 每秒画质损失的惩罚（相对最高档）
    public var wQuality: Double
    /// 每次切档的惩罚
    public var wSwitch: Double

    // MARK: - MPC 时域参数
    /// EWMA 平滑系数，越大越偏向最新观测
    public var alpha: Double
    /// MPC 预测步长 = segment 时长（秒）
    public var mpcDt: Double
    /// MPC 预测步数（H × dt = 窗口，必须显著大于 reservoir）
    public var horizon: Int

    // MARK: - 控制循环
    /// 控制循环周期（秒），与 Swift controlLoopInterval 一致
    public var controlLoopInterval: TimeInterval

    /// 与原硬编码默认值一致的配置
    public init(
        reservoir: Double = 5.0,
        cushion: Double = 10.0,
        hysteresis: Double = 0.8,
        wStall: Double = 100.0,
        wQuality: Double = 10.0,
        wSwitch: Double = 5.0,
        alpha: Double = 0.3,
        mpcDt: Double = 4.0,
        horizon: Int = 5,
        controlLoopInterval: TimeInterval = 0.5
    ) {
        self.reservoir = reservoir
        self.cushion = cushion
        self.hysteresis = hysteresis
        self.wStall = wStall
        self.wQuality = wQuality
        self.wSwitch = wSwitch
        self.alpha = alpha
        self.mpcDt = mpcDt
        self.horizon = horizon
        self.controlLoopInterval = controlLoopInterval
    }

    /// constitution v2.0 §5 要求的约束：预测窗口必须显著大于 reservoir，
    /// 否则 rollout 里 buffer 推不到 0、卡顿项恒为 0（见 spec-mpc.md CRITICAL）。
    public var satisfiesHorizonConstraint: Bool {
        Double(horizon) * mpcDt > reservoir * 2.0
    }
}
