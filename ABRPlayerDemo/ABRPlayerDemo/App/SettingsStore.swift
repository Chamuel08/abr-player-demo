//
//  SettingsStore.swift
//  ABRPlayerDemo
//
//  持久化所有 Settings 标量到 UserDefaults。app 重启后保留。
//  见 spec.md FR-7。
//
//  注意：@Observable 宏与 @AppStorage 属性包装器不兼容（宏生成的 init accessor
//  无法引用 @AppStorage 的 backing store）。因此这里用 @Observable + 存储属性 +
//  didSet 写 UserDefaults 的方式，既保留 @Observable 的访问追踪，又实现持久化。
//

import SwiftUI
import ABREngine

/// ABR 策略选择
enum ABRStrategy: String, CaseIterable, Identifiable {
    case bba = "BBA"
    case mpc = "MPC"
    var id: String { rawValue }
}

/// 所有持久化的 Settings 标量。
///
/// 用 `@Observable` + 存储属性 + `didSet` 写 UserDefaults。
/// `ABRConfig` 由这些标量构造后注入 `BBAController` / `MPCController`（见 PlayerViewModel）。
@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard

    // MARK: - ABR 策略
    var strategy: ABRStrategy {
        didSet { defaults.set(strategy.rawValue, forKey: "abr.strategy") }
    }

    // MARK: - BBA / MPC 共享 buffer 参数
    var reservoir: Double { didSet { defaults.set(reservoir, forKey: "abr.reservoir") } }
    var cushion: Double { didSet { defaults.set(cushion, forKey: "abr.cushion") } }
    var hysteresis: Double { didSet { defaults.set(hysteresis, forKey: "abr.hysteresis") } }

    // MARK: - MPC 代价权重
    var wStall: Double { didSet { defaults.set(wStall, forKey: "abr.wStall") } }
    var wQuality: Double { didSet { defaults.set(wQuality, forKey: "abr.wQuality") } }
    var wSwitch: Double { didSet { defaults.set(wSwitch, forKey: "abr.wSwitch") } }

    // MARK: - EWMA / MPC 时域
    var alpha: Double { didSet { defaults.set(alpha, forKey: "abr.alpha") } }
    var mpcDt: Double { didSet { defaults.set(mpcDt, forKey: "abr.mpcDt") } }
    var horizon: Int { didSet { defaults.set(horizon, forKey: "abr.horizon") } }

    // MARK: - 弱网 / 调试
    var weakNetwork: Bool { didSet { defaults.set(weakNetwork, forKey: "abr.weakNetwork") } }
    var autoWeakOnCellular: Bool { didSet { defaults.set(autoWeakOnCellular, forKey: "abr.autoWeakOnCellular") } }
    var debugPanelVisible: Bool { didSet { defaults.set(debugPanelVisible, forKey: "abr.debugPanelVisible") } }
    var qosLoggingEnabled: Bool { didSet { defaults.set(qosLoggingEnabled, forKey: "abr.qosLoggingEnabled") } }

    init() {
        let d = UserDefaults.standard
        self.strategy = ABRStrategy(rawValue: d.string(forKey: "abr.strategy") ?? "BBA") ?? .bba
        self.reservoir = d.object(forKey: "abr.reservoir") as? Double ?? 5.0
        self.cushion = d.object(forKey: "abr.cushion") as? Double ?? 10.0
        self.hysteresis = d.object(forKey: "abr.hysteresis") as? Double ?? 0.8
        self.wStall = d.object(forKey: "abr.wStall") as? Double ?? 100.0
        self.wQuality = d.object(forKey: "abr.wQuality") as? Double ?? 10.0
        self.wSwitch = d.object(forKey: "abr.wSwitch") as? Double ?? 5.0
        self.alpha = d.object(forKey: "abr.alpha") as? Double ?? 0.3
        self.mpcDt = d.object(forKey: "abr.mpcDt") as? Double ?? 4.0
        self.horizon = d.object(forKey: "abr.horizon") as? Int ?? 5
        self.weakNetwork = d.object(forKey: "abr.weakNetwork") as? Bool ?? false
        self.autoWeakOnCellular = d.object(forKey: "abr.autoWeakOnCellular") as? Bool ?? false
        self.debugPanelVisible = d.object(forKey: "abr.debugPanelVisible") as? Bool ?? false
        self.qosLoggingEnabled = d.object(forKey: "abr.qosLoggingEnabled") as? Bool ?? false
    }

    /// 由当前 Settings 构造 ABRConfig，注入 ABR 控制器
    func makeConfig() -> ABRConfig {
        ABRConfig(
            reservoir: reservoir,
            cushion: cushion,
            hysteresis: hysteresis,
            wStall: wStall,
            wQuality: wQuality,
            wSwitch: wSwitch,
            alpha: alpha,
            mpcDt: mpcDt,
            horizon: horizon
        )
    }
}
