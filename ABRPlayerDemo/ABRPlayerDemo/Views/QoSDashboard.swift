//
//  QoSDashboard.swift
//  ABRPlayerDemo
//
//  SPDD-generated: QoS 实时面板（7 项指标）
//

import SwiftUI

/// QoS 实时面板，显示 constitution §4 定义的 7 项指标
struct QoSDashboard: View {
    let metrics: QoSMetrics

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QoS 实时面板")
                .font(.headline)
                .foregroundColor(.primary)

            LazyVGrid(columns: columns, spacing: 8) {
                metricCell(title: "当前码率", value: metrics.currentBitrateString)
                metricCell(title: "观测吞吐", value: metrics.observedBitrateString)
                metricCell(title: "预测吞吐", value: metrics.estimatedThroughputString)
                metricCell(title: "Buffer 水位", value: metrics.bufferString)
                metricCell(title: "首帧耗时", value: metrics.firstFrameString)
                metricCell(title: "切档次数", value: "\(metrics.switchCount) 次")
                metricCell(title: "卡顿次数", value: "\(metrics.stallCount) 次")
                metricCell(title: "当前档位", value: metrics.currentVariantString)
                metricCell(title: "累计代价 J", value: metrics.cumulativeCostString)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func metricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
