//
//  NetworkMonitor.swift
//  ABRPlayerDemo
//
//  NWPathMonitor 网络监控。暴露 WiFi/cellular/none。
//  接入 Settings 自动弱网（autoWeakOnCellular）+ QoS 面板显示网络类型。
//  见 spec.md FR-10。
//

import Foundation
import Network

/// 网络类型
enum NetworkType: String {
    case wifi = "WiFi"
    case cellular = "蜂窝"
    case none = "无网络"
}

/// 网络监控器
final class NetworkMonitor: ObservableObject {
    @Published private(set) var type: NetworkType = .none
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "abr.networkmonitor")

    var description: String { type.rawValue }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status != .satisfied {
                    self?.type = .none
                } else if path.usesInterfaceType(.wifi) {
                    self?.type = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.type = .cellular
                } else {
                    self?.type = .wifi
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
