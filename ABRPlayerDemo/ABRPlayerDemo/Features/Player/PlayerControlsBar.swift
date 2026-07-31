//
//  PlayerControlsBar.swift
//  ABRPlayerDemo
//
//  播放器控制条：play/pause、scrubber + 时间标签、PiP 按钮、AirPlay、策略 picker。
//  见 spec.md FR-1、FR-5、plan.md §2.2。
//

import SwiftUI
import AVKit

struct PlayerControlsBar: View {
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onToggleQoS: () -> Void
    let onRequestPiP: () -> Void

    @Binding var strategy: ABRStrategy
    let onStrategyChange: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onToggleQoS) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("QoS 调试面板")

                AirPlayButton()
                    .frame(width: 32, height: 32)

                Button(action: onRequestPiP) {
                    Image(systemName: "pip.enter")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("画中画")
            }

            Picker("策略", selection: $strategy) {
                Text("BBA").tag(ABRStrategy.bba)
                Text("MPC").tag(ABRStrategy.mpc)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .onChange(of: strategy) { _, _ in onStrategyChange() }
        }
    }
}

/// AVRoutePickerView 的 SwiftUI 包装（AirPlay）
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.activeTintColor = .systemBlue
        v.tintColor = .label
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
