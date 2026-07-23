//
//  PlayerView.swift
//  ABRPlayerDemo
//
//  SPDD-generated: SwiftUI 的 AVPlayerLayer 包装（UIViewRepresentable）
//

import AVFoundation
import SwiftUI
import UIKit

/// 用 UIViewRepresentable 把 AVPlayerLayer 包装到 SwiftUI
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.player != player {
            uiView.player = player
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

    private var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            let l = AVPlayerLayer()
            l.videoGravity = .resizeAspect
            self.layer.addSublayer(l)
            return l
        }
        return layer
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
