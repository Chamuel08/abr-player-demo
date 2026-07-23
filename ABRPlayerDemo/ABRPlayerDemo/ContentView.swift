//
//  ContentView.swift
//  ABRPlayerDemo
//
//  SPDD-generated: 主 UI（播放器 + QoS 面板 + 切档日志）
//

import SwiftUI

struct ContentView: View {
    @StateObject private var controller: ABRPlayerController

    init() {
        // Apple BipBop 多码率测试流
        let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")!
        _controller = StateObject(wrappedValue: ABRPlayerController(url: url))
    }

    var body: some View {
        VStack(spacing: 12) {
            // 上半部分：播放器
            PlayerView(player: controller.player)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .background(Color.black)
                .cornerRadius(8)

            // 控制条
            HStack {
                Button(action: {
                    if controller.isPlaying {
                        controller.pause()
                    } else {
                        controller.play()
                    }
                }) {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle("模拟弱网", isOn: $controller.simulateWeakNetwork)
                    .toggleStyle(SwitchToggleStyle(tint: .red))
                    .font(.caption)
            }
            .padding(.horizontal, 12)

            // 下半部分：QoS 面板
            QoSDashboard(metrics: controller.metrics)

            // 切档日志
            SwitchLogView(logs: controller.switchLogs)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.systemGroupedBackground))
        .task {
            controller.play()
        }
    }
}

#Preview {
    ContentView()
}
