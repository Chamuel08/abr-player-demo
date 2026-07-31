//
//  ThroughputEstimatorTests.swift
//  ABREngineTests
//

import XCTest
@testable import ABREngine

final class ThroughputEstimatorTests: XCTestCase {

    func testFirstObservationAdoptedDirectly() {
        var est = ThroughputEstimator(alpha: 0.3)
        let v = est.feed(observed: 1_000_000)
        XCTAssertEqual(v, 1_000_000, "首次观测应直接采用，避免从 0 缓慢爬升")
        XCTAssertEqual(est.current, 1_000_000)
    }

    func testEWMAConvergence() {
        var est = ThroughputEstimator(alpha: 0.3)
        _ = est.feed(observed: 1_000_000)
        // 持续喂 2_000_000，EWMA 应向 2_000_000 收敛但不超过
        for _ in 0..<100 {
            _ = est.feed(observed: 2_000_000)
        }
        XCTAssertLessThan(est.current, 2_000_000)
        XCTAssertGreaterThan(est.current, 1_900_000, "长期喂 2M 应收敛到接近 2M")
    }

    func testNonPositiveObservedIgnored() {
        var est = ThroughputEstimator(alpha: 0.3)
        _ = est.feed(observed: 1_000_000)
        let before = est.current
        _ = est.feed(observed: 0)
        XCTAssertEqual(est.current, before, "observed=0 应被忽略")
        _ = est.feed(observed: -100)
        XCTAssertEqual(est.current, before, "observed<0 应被忽略")
    }

    func testAlphaControlsResponsiveness() {
        // 大 α 更偏向最新观测
        var fastEst = ThroughputEstimator(alpha: 0.9)
        _ = fastEst.feed(observed: 1_000_000)
        let fastV = fastEst.feed(observed: 2_000_000)
        // 0.9*2M + 0.1*1M = 1.9M
        XCTAssertEqual(fastV, 1_900_000, accuracy: 1.0)

        var slowEst = ThroughputEstimator(alpha: 0.1)
        _ = slowEst.feed(observed: 1_000_000)
        let slowV = slowEst.feed(observed: 2_000_000)
        // 0.1*2M + 0.9*1M = 1.1M
        XCTAssertEqual(slowV, 1_100_000, accuracy: 1.0)
    }

    func testReset() {
        var est = ThroughputEstimator(alpha: 0.3)
        _ = est.feed(observed: 1_000_000)
        est.reset()
        XCTAssertEqual(est.current, 0)
        // reset 后首次观测再次直接采用
        let v = est.feed(observed: 500_000)
        XCTAssertEqual(v, 500_000)
    }
}
