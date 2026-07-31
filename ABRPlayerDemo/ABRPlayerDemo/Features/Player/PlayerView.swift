//
//  PlayerView.swift
//  ABRPlayerDemo
//
//  SwiftUI 的 AVPlayerLayer 包装（UIViewRepresentable）。
//  暴露 AVPlayerLayer 引用给 PiPCoordinator 使用。
//

import AVFoundation
import SwiftUI
import UIKit

/// 用 UIViewRepresentable 把 AVPlayerLayer 包装到 SwiftUI
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    /// 暴露 layer 引用，供 PiPCoordinator 绑定
    var playerLayerRef: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        view.backgroundColor = .black
        DispatchQueue.main.async {
            playerLayerRef?(view.playerLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.player != player {
            uiView.player = player
            playerLayerRef?(uiView.playerLayer)
        }
    }
}

/// 承载 AVPlayerLayer 的 UIView
final class PlayerUIView: UIView {
    var player: AVPlayer? {
        didSet {
            if player !== oldValue {
                playerLayer.player = player
            }
        }
    }

    var playerLayer: AVPlayerLayer {
        if let layer = layer as? AVPlayerLayer {
            return layer
        }
        let l = AVPlayerLayer()
        l.videoGravity = .resizeAspect
        self.layer.addSublayer(l)
        return l
    }

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        guard let layer = self.layer as? AVPlayerLayer else { return }
        layer.videoGravity = .resizeAspect
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layer = self.layer as? AVPlayerLayer else { return }
        layer.frame = self.bounds
    }
}
