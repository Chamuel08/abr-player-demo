#!/usr/bin/env python3
"""Dump BBA/MPC decision sequences on a fixed synthetic trace for Swift parity tests.

输出格式：每行 `tick,buffer,observed,target`（BBA）或
`tick,buffer,observed,est_throughput,current_bitrate,recompute,target`（MPC）。
Swift 测试读取这些期望值，用相同的 (buffer, observed, ...) 喂 decide()，断言 target 一致。

注意：BBA 的 decide 不依赖 observed，但仿真器的 buffer 动力学依赖 target×observed，
所以 buffer 序列本身是 target 的反馈结果。为避免在 Swift 侧重放 buffer 动力学，
这里直接把仿真器每拍的 (buffer, observed, target) 三元组导出，Swift 侧只需
用 buffer 调 decide()、对比 target 即可——这检验的是决策函数本身，不是仿真器。
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))

from simulate_abr import BBAPolicy, MPCPolicy, Trace, DEFAULTS, DT

# 固定合成 trace：吞吐在 0.3 Mbps 和 2.0 Mbps 之间方波振荡，每 10 秒切换一次，
# 持续 60 秒。这能触发升档、降档、滞回等多种决策路径。
def make_synthetic_trace():
    times = list(range(0, 61))
    mbps = []
    for t in times:
        # 方波：前 10s 高、后 10s 低、循环
        if (t // 10) % 2 == 0:
            mbps.append(2.0)
        else:
            mbps.append(0.3)
    return Trace("synthetic_parity", times, mbps, scale=1.0)

# 用 Mux 阶梯（与 simulate_abr.py 默认一致），5 档跨度大、能区分决策
LADDER = [246440.0, 460560.0, 836280.0, 2149280.0, 6221600.0]

def dump_bba():
    params = dict(DEFAULTS)
    policy = BBAPolicy(LADDER, params)
    trace = make_synthetic_trace()
    # 手动跑仿真循环，每拍记录 (buffer, observed, target)
    # 这里我们只关心 decide() 的输入输出，不复用 simulate() 的完整 Result
    buffer_sec = 0.0
    target = LADDER[0]
    rows = []
    t = 0.0
    sim_duration = 60.0
    while t < sim_duration:
        observed = trace.throughput_at(t)
        new_target = policy.decide(buffer_sec, observed, weak_network=False, now=t)
        rows.append((round(t, 4), round(buffer_sec, 6), round(observed, 2), round(new_target, 2)))
        if new_target != target:
            target = new_target
        policy.commit(target)
        # buffer 动力学（与 simulate() 一致）
        if target > 0 and observed > 0 and buffer_sec < 60.0:
            buffer_sec += observed * DT / target
            buffer_sec = min(buffer_sec, 60.0)
        buffer_sec = max(0, buffer_sec - DT)
        t += DT
    return rows

def dump_mpc():
    params = dict(DEFAULTS)
    policy = MPCPolicy(LADDER, params)
    trace = make_synthetic_trace()
    buffer_sec = 0.0
    target = LADDER[0]
    rows = []
    t = 0.0
    sim_duration = 60.0
    while t < sim_duration:
        observed = trace.throughput_at(t)
        current_br = target
        # 注意：不单独调 _should_recompute——decide() 内部会调，单独调会双重 mutate
        # last_rollout_time，导致 decide() 内部的判定返回 False。这里只调 decide()，
        # 让它内部自行判定 segment 边界，与 simulate() 的真实路径一致。
        new_target = policy.decide(buffer_sec, observed, weak_network=False, now=t)
        rows.append((round(t, 4), round(buffer_sec, 6), round(observed, 2),
                     round(policy.estimated_throughput, 2), round(current_br, 2),
                     round(new_target, 2)))
        if new_target != target:
            target = new_target
        policy.commit(target)
        if target > 0 and observed > 0 and buffer_sec < 60.0:
            buffer_sec += observed * DT / target
            buffer_sec = min(buffer_sec, 60.0)
        buffer_sec = max(0, buffer_sec - DT)
        t += DT
    return rows

if __name__ == "__main__":
    print("=== BBA parity (tick, buffer, observed, target) ===")
    for r in dump_bba():
        print("%g,%.6f,%.2f,%.2f" % r)
    print()
    print("=== MPC parity (tick, buffer, observed, est_throughput, current_bitrate, recompute, target) ===")
    for r in dump_mpc():
        print("%g,%.6f,%.2f,%.2f,%.2f,%d,%.2f" % r)
