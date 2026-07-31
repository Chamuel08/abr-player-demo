//
//  SwitchLogView.swift
//  ABRPlayerDemo
//
//  切档日志列表（移自旧 Views/，作为 QoS 调试 sheet 内组件）。
//

import SwiftUI
import ABREngine

struct SwitchLogView: View {
    let logs: [SwitchLog]

    var body: some View {
        List {
            if logs.isEmpty {
                Text("暂无切档记录")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logs.reversed()) { log in
                    Text(log.displayString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.plain)
    }
}
