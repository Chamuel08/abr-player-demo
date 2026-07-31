//
//  ABRLogger.swift
//  ABREngine
//
//  os.Logger 封装，替代各控制器内的 print()。
//  按 subsystem com.abrplayer.demo.engine 分通道，便于 Console.app 过滤。
//

import Foundation
import OSLog

/// ABR 引擎统一日志入口
public enum ABRLogger {
    /// 日志子系统（app 与引擎共用，便于 Console.app 过滤）
    public static let subsystem = "com.abrplayer.demo.engine"

    /// 决策通道（每 0.5s 的选档决策）
    public static let decision = Logger(subsystem: subsystem, category: "decision")
    /// 切档通道（target 变化）
    public static let switching = Logger(subsystem: subsystem, category: "switching")
    /// 卡顿通道（timeControlStatus 翻转）
    public static let stall = Logger(subsystem: subsystem, category: "stall")
    /// 错误通道（档位解析失败、播放失败等）
    public static let error = Logger(subsystem: subsystem, category: "error")
    /// QoS 通道（采样写入）
    public static let qos = Logger(subsystem: subsystem, category: "qos")
}
