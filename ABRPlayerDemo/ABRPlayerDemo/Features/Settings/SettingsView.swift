//
//  SettingsView.swift
//  ABRPlayerDemo
//
//  设置页：参数 sliders、策略选择、弱网开关、CSV 导出按钮、清空历史。
//  见 spec.md FR-7、plan.md §2.2。
//

import SwiftUI
import SwiftData
import ABREngine

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var recents: [PlaybackHistoryItem]
    @State private var csvURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("ABR 策略") {
                    Picker("策略", selection: Binding(
                        get: { env.settings.strategy },
                        set: { env.settings.strategy = $0 }
                    )) {
                        Text("BBA").tag(ABRStrategy.bba)
                        Text("MPC").tag(ABRStrategy.mpc)
                    }
                    .pickerStyle(.segmented)
                }

                Section("BBA / MPC 共享 buffer 参数") {
                    parameterSlider("reservoir", binding: Binding(get: { env.settings.reservoir }, set: { env.settings.reservoir = $0 }), range: 1...20, step: 0.5, unit: "s")
                    parameterSlider("cushion", binding: Binding(get: { env.settings.cushion }, set: { env.settings.cushion = $0 }), range: 1...30, step: 0.5, unit: "s")
                    parameterSlider("hysteresis", binding: Binding(get: { env.settings.hysteresis }, set: { env.settings.hysteresis = $0 }), range: 0.5...0.95, step: 0.05, unit: "")
                }

                Section("MPC 代价权重") {
                    parameterSlider("w_stall", binding: Binding(get: { env.settings.wStall }, set: { env.settings.wStall = $0 }), range: 1...200, step: 1, unit: "")
                    parameterSlider("w_quality", binding: Binding(get: { env.settings.wQuality }, set: { env.settings.wQuality = $0 }), range: 1...50, step: 1, unit: "")
                    parameterSlider("w_switch", binding: Binding(get: { env.settings.wSwitch }, set: { env.settings.wSwitch = $0 }), range: 1...50, step: 1, unit: "")
                }

                Section("EWMA / MPC 时域") {
                    parameterSlider("alpha (EWMA)", binding: Binding(get: { env.settings.alpha }, set: { env.settings.alpha = $0 }), range: 0.05...0.95, step: 0.05, unit: "")
                    parameterSlider("mpc_dt (segment)", binding: Binding(get: { env.settings.mpcDt }, set: { env.settings.mpcDt = $0 }), range: 1...10, step: 0.5, unit: "s")
                    Stepper("horizon: \(env.settings.horizon)", value: Binding(get: { env.settings.horizon }, set: { env.settings.horizon = $0 }), in: 1...20)
                }

                Section("弱网 / 调试") {
                    Toggle("模拟弱网", isOn: Binding(get: { env.settings.weakNetwork }, set: { env.settings.weakNetwork = $0 }))
                    Toggle("蜂窝自动弱网", isOn: Binding(get: { env.settings.autoWeakOnCellular }, set: { env.settings.autoWeakOnCellular = $0 }))
                    Toggle("QoS 采样写入", isOn: Binding(get: { env.settings.qosLoggingEnabled }, set: { env.settings.qosLoggingEnabled = $0 }))
                    Toggle("默认显示调试面板", isOn: Binding(get: { env.settings.debugPanelVisible }, set: { env.settings.debugPanelVisible = $0 }))
                }

                Section("数据") {
                    Button("导出 QoS 日志 (CSV)") { exportCSV() }
                    Button("清空播放历史", role: .destructive) { clearHistory() }
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showShareSheet) {
                if let csvURL { ShareSheet(items: [csvURL]) }
            }
        }
    }

    private func parameterSlider(_ title: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: step < 1 ? "%.2f%@" : "%.0f%@", binding.wrappedValue, unit))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: binding, in: range, step: step)
        }
    }

    private func exportCSV() {
        do {
            csvURL = try QoSLogExporter.export(sessionID: nil, from: env.modelContext)
            showShareSheet = true
        } catch {
            ABRLogger.error.error("CSV 导出失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearHistory() {
        for r in recents { env.modelContext.delete(r) }
        try? env.modelContext.save()
    }
}

/// UIActivityViewController 的 SwiftUI 包装（CSV 导出分享）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
