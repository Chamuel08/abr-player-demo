//
//  BBAPolicyParityTests.swift
//  ABREngineTests
//
//  守 constitution v2.0 §5：BBAController.decide 在固定合成 trace 上的决策序列
//  必须与 scripts/simulate_abr.py 的 BBAPolicy 逐拍一致。
//
//  期望值由 scripts/emit_parity_swift.py 从 Python 仿真器导出（见 ParityFixtures.swift）。
//  改 simulate_abr.py 的 BBAPolicy 逻辑后必须重生成 ParityFixtures.swift。
//

import XCTest
import AVFoundation
@testable import ABREngine

final class BBAPolicyParityTests: XCTestCase {

    // 与 simulate_abr.py 的 LADDER_MUX 一致
    private let ladder: [Double] = [246440.0, 460560.0, 836280.0, 2149280.0, 6221600.0]

    func testDecideSequenceMatchesPythonSimulator() throws {
        // BBAController 需要 AVPlayer，但 decide() 是纯函数，不读 player。
        // 用一个空 AVPlayer 构造，只调 decide() + commit()，不调 start()/controlLoop()。
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let controller = BBAController(player: player, variants: variants, config: ABRConfig())

        for (i, row) in bbaParityFixture.enumerated() {
            let target = controller.decide(bufferSeconds: row.buffer)
            XCTAssertEqual(target, row.target, accuracy: 1.0,
                           "tick \(i): buffer=\(row.buffer) 期望 \(row.target)，实际 \(target)")
            controller.commit(target)
        }
    }

    func testWeakNetworkForcesLowest() {
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let controller = BBAController(player: player, variants: variants, config: ABRConfig())
        controller.simulateWeakNetwork = true

        // 任何 buffer 下都应强制最低档
        for buffer in [0.0, 5.0, 10.0, 20.0, 100.0] {
            XCTAssertEqual(controller.decide(bufferSeconds: buffer), ladder[0],
                           "弱网下 buffer=\(buffer) 应强制最低档")
        }
    }

    func testReservoirFloor() {
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let controller = BBAController(player: player, variants: variants, config: ABRConfig())

        // buffer < reservoir(5) 强制最低档
        XCTAssertEqual(controller.decide(bufferSeconds: 4.9), ladder[0])
        XCTAssertEqual(controller.decide(bufferSeconds: 0.0), ladder[0])
    }

    func testCushionCeiling() {
        let player = AVPlayer()
        let variants = ladder.map { HLSVariant(peakBitRate: $0, url: URL(string: "https://example.com")!) }
        let controller = BBAController(player: player, variants: variants, config: ABRConfig())

        // buffer > reservoir+cushion(15) 冲最高档
        XCTAssertEqual(controller.decide(bufferSeconds: 15.1), ladder.last!)
        XCTAssertEqual(controller.decide(bufferSeconds: 100.0), ladder.last!)
    }
}
