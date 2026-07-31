//
//  AudioSessionManager.swift
//  ABRPlayerDemo
//
//  AVAudioSession 配置 + 中断/路由通知监听。见 spec.md FR-9。
//

import AVFoundation
import Foundation
import ABREngine

/// 音频会话管理器：配置 .playback，监听中断与路由变化
final class AudioSessionManager {
    private var observers: [NSObjectProtocol] = []

    /// 配置音频会话并开始监听
    func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            ABRLogger.error.error("音频会话配置失败: \(error.localizedDescription, privacy: .public)")
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            ABRLogger.qos.info("audio route changed")
        })
    }

    deinit {
        for o in observers {
            NotificationCenter.default.removeObserver(o)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            ABRLogger.qos.warning("audio interruption began")
        case .ended:
            ABRLogger.qos.info("audio interruption ended")
            try? AVAudioSession.sharedInstance().setActive(true)
        @unknown default:
            break
        }
    }
}
