//
//  AppEnvironment.swift
//  ABRPlayerDemo
//
//  @Observable 依赖容器，持有 SettingsStore / SwiftData ModelContainer。
//  注入 SwiftUI Environment，供各 Feature 视图共享。见 plan.md §2.2。
//

import SwiftUI
import SwiftData

/// 全局依赖容器
@Observable
final class AppEnvironment {
    let settings: SettingsStore
    let modelContainer: ModelContainer

    init(settings: SettingsStore = SettingsStore(),
         modelContainer: ModelContainer? = nil) {
        self.settings = settings
        if let modelContainer {
            self.modelContainer = modelContainer
        } else {
            do {
                self.modelContainer = try ModelContainer(
                    for: PlaybackHistoryItem.self, QoSLogEntry.self
                )
            } catch {
                fatalError("无法创建 ModelContainer: \(error)")
            }
        }
    }

    var modelContext: ModelContext {
        MainActor.assumeIsolated { modelContainer.mainContext }
    }
}
