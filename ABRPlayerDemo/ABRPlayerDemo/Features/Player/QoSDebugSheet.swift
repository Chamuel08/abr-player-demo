//
//  QoSDebugSheet.swift
//  ABRPlayerDemo
//
//  QoS 调试 sheet（移自旧 Views/QoSDashboard.swift）。
//  含 7 项指标 + 切档日志入口。默认不可见，由用户主动打开。
//  见 constitution v2.0 §4、spec.md FR-3。
//

import SwiftUI
import ABREngine

struct QoSDebugSheet: View {
    let metrics: QoSMetrics
    let logs: [SwitchLog]
    let networkType: String

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("QoS 实时面板")
                        .font(.headline)

                    LazyVGrid(columns: columns, spacing: 8) {
                        metricCell("当前码率", metrics.currentBitrateString)
                        metricCell("观测吞吐", metrics.observedBitrateString)
                        metricCell("预测吞吐", metrics.estimatedThroughputString)
                        metricCell("Buffer 水位", metrics.bufferString)
                        metricCell("首帧耗时", metrics.firstFrameString)
                        metricCell("切档次数", "\(metrics.switchCount) 次")
                        metricCell("卡顿次数", "\(metrics.stallCount) 次")
                        metricCell("当前档位", metrics.currentVariantString)
                        metricCell("累计代价 J", metrics.cumulativeCostString)
                        metricCell("网络类型", networkType)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("切档日志（最近 10 条）")
                            .font(.headline)
                        SwitchLogView(logs: logs)
                            .frame(minHeight: 200)
                    }
                }
                .padding()
            }
            .navigationTitle("QoS 调试")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func metricCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}
