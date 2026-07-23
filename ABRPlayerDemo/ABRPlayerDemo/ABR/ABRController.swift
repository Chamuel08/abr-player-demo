//
//  ABRController.swift
//  ABRPlayerDemo
//
//  SPDD-generated: ABR 策略抽象协议，统一 BBA / MPC 的对外接口
//

import Foundation

/// ABR 策略控制器协议
///
/// BBA 与 MPC 均遵循此协议，便于 `ABRPlayerController` 在运行时切换策略。
/// 协议只规定对外接口；控制循环（Timer）、决策算法由实现各自负责。
protocol ABRController: AnyObject {
    /// 当前目标码率（bps），nil 表示尚未决策
    var currentTarget: Double? { get }
    /// 累计切档次数
    var switchCount: Int { get }
    /// 模拟弱网模式（开启后强制最低档）
    var simulateWeakNetwork: Bool { get set }
    /// 切档回调，UI 订阅用
    var onSwitch: ((SwitchLog) -> Void)? { get set }
    /// 可用档位（按码率升序）
    var variants: [HLSVariant] { get }

    /// 启动控制循环
    func start()
    /// 停止控制循环
    func stop()
}
