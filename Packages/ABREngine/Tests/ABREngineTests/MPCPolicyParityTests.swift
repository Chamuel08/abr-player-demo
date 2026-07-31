//
//  MPCPolicyParityTests.swift
//  ABREngineTests
//
//  守 constitution v2.0 §5：MPCController.decide 在固定合成 trace 上的决策序列
//  必须与 scripts/simulate_abr.py 的 MPCPolicy 逐拍一致。
//
//  测试侧自行用 ThroughputEstimator + shouldRecomputeRollout 复现 EWMA/segment 边界
//  （与 MPCController.controlLoop 同构），再调 decide() 对比 target。
//

import XCTest
import AVFoundation
@testable import ABREngine

final class MPCPolicyParityTests: XCTestCase {

    private let ladder: [Double] = [246440.0, 460560.0, 836280.0, 2149280.0, 6221600.0]

    func testDecideSequenceMatchesPythonSimulator() throws {
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let config = ABRConfig()
        let controller = MPCController(player: player, variants: variants, config: config)

        // 测试侧复现 controlLoop 的 EWMA + segment 边界逻辑（不依赖 AVPlayer）
        var estimator = ThroughputEstimator(alpha: config.alpha)
        var currentBitrate = ladder[0]

        for (i, row) in mpcParityFixture.enumerated() {
            // EWMA 更新（与 MPCController.controlLoop 一致：observed>0 才喂）
            if row.observed > 0 {
                _ = estimator.feed(observed: row.observed)
            }
            let estThroughput = estimator.current

            // segment 边界判定
            let recompute = controller.shouldRecomputeRollout(at: row.tick)

            let target = controller.decide(bufferSeconds: row.buffer,
                                           estimatedThroughput: estThroughput,
                                           currentBitrate: currentBitrate,
                                           recomputeRollout: recompute)
            XCTAssertEqual(target, row.target, accuracy: 1.0,
                           "tick \(i)(t=\(row.tick)): buffer=\(row.buffer) est=\(estThroughput) recompute=\(recompute) 期望 \(row.target)，实际 \(target)")
            if target != currentBitrate {
                currentBitrate = target
            }
            controller.commit(target)
        }
    }

    func testSafetyFallbackBufferBelowReservoir() {
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let controller = MPCController(player: player, variants: variants, config: ABRConfig())

        // buffer < reservoir 强制最低档，即使吞吐充足
        let target = controller.decide(bufferSeconds: 4.0,
                                        estimatedThroughput: 10_000_000,
                                        currentBitrate: ladder.last!,
                                        recomputeRollout: true)
        XCTAssertEqual(target, ladder[0])
    }

    func testSafetyFallbackNoThroughput() {
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let controller = MPCController(player: player, variants: variants, config: ABRConfig())

        // 无吞吐观测强制最低档
        let target = controller.decide(bufferSeconds: 20.0,
                                        estimatedThroughput: 0,
                                        currentBitrate: ladder.last!,
                                        recomputeRollout: true)
        XCTAssertEqual(target, ladder[0])
    }

    func testSafetyFallbackWeakNetwork() {
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let controller = MPCController(player: player, variants: variants, config: ABRConfig())
        controller.simulateWeakNetwork = true

        let target = controller.decide(bufferSeconds: 20.0,
                                        estimatedThroughput: 10_000_000,
                                        currentBitrate: ladder.last!,
                                        recomputeRollout: true)
        XCTAssertEqual(target, ladder[0])
    }

    func testHorizonConstraint() {
        // ABRConfig.satisfiesHorizonConstraint：窗口必须显著大于 reservoir
        let ok = ABRConfig(reservoir: 5.0, mpcDt: 4.0, horizon: 5)  // 20s > 10s
        XCTAssertTrue(ok.satisfiesHorizonConstraint)
        let bad = ABRConfig(reservoir: 5.0, mpcDt: 0.5, horizon: 10)  // 5s ≈ reservoir
        XCTAssertFalse(bad.satisfiesHorizonConstraint)
    }
}
