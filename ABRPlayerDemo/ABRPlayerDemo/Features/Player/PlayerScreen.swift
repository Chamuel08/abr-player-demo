//
//  PlayerScreen.swift
//  ABRPlayerDemo
//
//  播放器主屏：替代旧 ContentView。全屏播放 + 控制条 + 调试 sheet 入口 + 错误 overlay。
//  见 plan.md §2.2。
//

import SwiftUI
import AVFoundation
import ABREngine

struct PlayerScreen: View {
    let stream: StreamItem

    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PlayerViewModel?
    @State private var showQoS = false
    @State private var playerLayerRef: AVPlayerLayer?
    @State private var pipCoordinator: PiPCoordinator?
    @State private var lifecycle: LifecycleHandler?
    @State private var audioSession = AudioSessionManager()
    @State private var networkMonitor = NetworkMonitor()

    var body: some View {
        VStack(spacing: 12) {
            PlayerView(player: viewModel?.player ?? AVPlayer(),
                       playerLayerRef: { layer in playerLayerRef = layer })
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)
                .cornerRadius(8)

            if let vm = viewModel {
                PlayerControlsBar(
                    isPlaying: vm.isPlaying,
                    onPlayPause: { vm.isPlaying ? vm.pause() : vm.play() },
                    onToggleQoS: { showQoS.toggle() },
                    onRequestPiP: { startPiP() },
                    strategy: Binding(
                        get: { env.settings.strategy },
                        set: { env.settings.strategy = $0 }
                    ),
                    onStrategyChange: { vm.rebuildABR() }
                )
                .padding(.horizontal, 12)
            }

            if let msg = viewModel?.errorMessage {
                ErrorOverlay(message: msg) {
                    viewModel?.errorMessage = nil
                    viewModel?.play()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.systemGroupedBackground))
        .task {
            if viewModel == nil {
                let vm = PlayerViewModel(stream: stream,
                                          settings: env.settings,
                                          modelContext: env.modelContext)
                viewModel = vm
                audioSession.activate()
                networkMonitor.start()
                setupLifecycle()
                vm.play()
            }
        }
        .onDisappear {
            viewModel?.stop()
            networkMonitor.stop()
            pipCoordinator?.stop()
        }
        .onChange(of: networkMonitor.type) { _, newType in
            applyAutoWeak(newType)
        }
        .sheet(isPresented: $showQoS) {
            if let vm = viewModel {
                QoSDebugSheet(metrics: vm.metrics, logs: vm.switchLogs,
                              networkType: networkMonitor.description)
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - 自动弱网（蜂窝时强制弱网，WiFi 时恢复）

    private func applyAutoWeak(_ type: NetworkType) {
        guard env.settings.autoWeakOnCellular else { return }
        let shouldWeak = (type == .cellular || type == .none)
        env.settings.weakNetwork = shouldWeak
        viewModel?.abr?.simulateWeakNetwork = shouldWeak
        ABRLogger.qos.info("auto-weak: type=\(type.rawValue) weak=\(shouldWeak)")
    }

    // MARK: - PiP

    private func startPiP() {
        guard let layer = playerLayerRef else { return }
        if pipCoordinator == nil {
            pipCoordinator = PiPCoordinator(playerLayer: layer)
        }
        pipCoordinator?.start()
    }

    // MARK: - 生命周期

    private func setupLifecycle() {
        lifecycle = LifecycleHandler(
            onBackground: { [weak viewModel] in
                if pipCoordinator?.isActive != true {
                    viewModel?.pause()
                }
            },
            onForeground: { [weak viewModel] in
                viewModel?.play()
            }
        )
    }
}

/// 播放失败错误 overlay
struct ErrorOverlay: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("播放失败")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
