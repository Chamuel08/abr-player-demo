//
//  PiPCoordinator.swift
//  ABRPlayerDemo
//
//  AVPictureInPictureController 生命周期管理，与 PlayerUIView 的 AVPlayerLayer 绑定。
//  见 spec.md FR-5、plan.md §2.2。
//

import AVFoundation
import AVKit
import Foundation
import ABREngine

/// 画中画协调器
final class PiPCoordinator {
    private weak var playerLayer: AVPlayerLayer?
    private var controller: AVPictureInPictureController?

    /// PiP 是否处于激活状态
    var isActive: Bool { controller?.isPictureInPictureActive ?? false }

    init(playerLayer: AVPlayerLayer) {
        self.playerLayer = playerLayer
        if AVPictureInPictureController.isPictureInPictureSupported() {
            controller = AVPictureInPictureController(playerLayer: playerLayer)
        }
    }

    func start() {
        guard let controller else {
            ABRLogger.qos.warning("PiP 不支持（模拟器或设备未启用）")
            return
        }
        controller.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }
}
