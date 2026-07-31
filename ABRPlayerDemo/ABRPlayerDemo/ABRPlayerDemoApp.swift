//
//  ABRPlayerDemoApp.swift
//  ABRPlayerDemo
//
//  @main 入口。创建 AppEnvironment 注入 Environment，TabView(Library / Settings)。
//

import SwiftUI
import SwiftData

@main
struct ABRPlayerDemoApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView()
                    .tabItem {
                        Label("内容库", systemImage: "list.bullet")
                    }
                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape")
                    }
            }
            .environment(env)
            .modelContainer(env.modelContainer)
        }
    }
}
