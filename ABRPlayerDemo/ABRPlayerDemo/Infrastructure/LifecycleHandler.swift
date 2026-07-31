//
//  LifecycleHandler.swift
//  ABRPlayerDemo
//
//  scenePhase 生命周期处理：后台暂停（PiP 激活时除外）、前台恢复。
//  见 spec.md FR-9、plan.md §2.2。
//

import SwiftUI
import Combine

/// 生命周期处理器：把 scenePhase 变化转成回调
final class LifecycleHandler: ObservableObject {
    private let onBackground: () -> Void
    private let onForeground: () -> Void

    init(onBackground: @escaping () -> Void, onForeground: @escaping () -> Void) {
        self.onBackground = onBackground
        self.onForeground = onForeground
    }

    /// 由 PlayerScreen 在 scenePhase 变化时调用
    func handle(scenePhase: ScenePhase, pipActive: Bool = false) {
        switch scenePhase {
        case .background, .inactive:
            if !pipActive {
                onBackground()
            }
        case .active:
            onForeground()
        @unknown default:
            break
        }
    }
}
