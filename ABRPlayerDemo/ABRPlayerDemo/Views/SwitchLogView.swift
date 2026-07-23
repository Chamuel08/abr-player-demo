//
//  SwitchLogView.swift
//  ABRPlayerDemo
//
//  SPDD-generated: 切档日志面板（最近 10 条）
//

import SwiftUI

/// 切档日志面板，显示最近 10 条切档决策
struct SwitchLogView: View {
    let logs: [SwitchLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("切档日志")
                    .font(.headline)
                Spacer()
                Text("共 \(logs.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if logs.isEmpty {
                Text("暂无切档记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(logs.reversed()) { log in
                            Text(log.displayString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
