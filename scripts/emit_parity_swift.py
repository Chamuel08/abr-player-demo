#!/usr/bin/env python3
"""Emit Swift test data (array literals) for ABREngineTests from the parity dump.

输出两段 Swift 代码：BBA 期望序列、MPC 期望序列，直接粘贴进
Tests/ABREngineTests/ParityFixtures.swift。
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))

from dump_parity_trace import dump_bba, dump_mpc

def emit_bba():
    rows = dump_bba()
    lines = []
    lines.append("// 由 scripts/emit_parity_swift.py 生成。改 simulate_abr.py 策略逻辑后必须重生成。")
    lines.append("// 每个元素：(buffer_seconds, expected_target_bps)")
    lines.append("public let bbaParityFixture: [(buffer: Double, target: Double)] = [")
    for tick, buffer, observed, target in rows:
        lines.append("    (buffer: %.6f, target: %.2f)," % (buffer, target))
    lines.append("]")
    return "\n".join(lines)

def emit_mpc():
    rows = dump_mpc()
    lines = []
    lines.append("// 由 scripts/emit_parity_swift.py 生成。改 simulate_abr.py 策略逻辑后必须重生成。")
    lines.append("// 每个元素：(tick, buffer_seconds, observed_bps, expected_target_bps)")
    lines.append("// 测试侧自行用 ThroughputEstimator + shouldRecomputeRollout 复现 EWMA/segment 边界，")
    lines.append("// 再调 decide(buffer, est, currentBitrate, recompute) 对比 target。")
    lines.append("public let mpcParityFixture: [(tick: Double, buffer: Double, observed: Double, target: Double)] = [")
    for tick, buffer, observed, est, cur, target in rows:
        lines.append("    (tick: %g, buffer: %.6f, observed: %.2f, target: %.2f)," % (tick, buffer, observed, target))
    lines.append("]")
    return "\n".join(lines)

if __name__ == "__main__":
    print(emit_bba())
    print()
    print(emit_mpc())
