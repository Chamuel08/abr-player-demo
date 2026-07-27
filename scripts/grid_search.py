#!/usr/bin/env python3
"""ABR 参数网格搜索：训练集搜参、测试集报数，输出 QoE 最优参数与 Pareto 前沿。

纪律（见 specs/abr-player-demo/spec-calibration.md）：
  - 训练集 fcc_and_hsdpa/cooked_traces 搜参，测试集 cooked_test_traces 报数，避免过拟合。
  - 搜出来的参数是"候选"，必须过真机验收（Network Link Conditioner + 真实 HLS 流）
    才能写回 BBAController.swift / MPCController.swift。

用法：
    python3 scripts/grid_search.py                        # BBA 默认网格
    python3 scripts/grid_search.py --strategy mpc         # MPC（含代价权重）
    python3 scripts/grid_search.py --jobs 8 --limit 80
"""

import argparse
import itertools
import os
import sys
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from simulate_abr import (  # noqa: E402
    DEFAULTS, LADDERS, POLICIES, aggregate, load_dataset, run_dataset,
)

# 搜索网格。BBA 只有三个 buffer 参数；MPC 额外搜代价权重。
GRID_BBA = {
    "reservoir": [3.0, 4.0, 5.0, 6.0, 8.0],
    "cushion": [6.0, 8.0, 10.0, 12.0, 15.0],
    "hysteresis": [0.6, 0.7, 0.8, 0.9, 0.95],
}
GRID_MPC = {
    "reservoir": [3.0, 5.0, 8.0],
    "cushion": [6.0, 10.0, 15.0],
    "hysteresis": [0.7, 0.8, 0.9],
    "w_stall": [50.0, 100.0, 200.0],
    "w_quality": [5.0, 10.0, 20.0],
    "w_switch": [5.0, 25.0, 100.0],
}

_CTX = {}


def _init(strategy, ladder, train, test, duration):
    _CTX.update(strategy=strategy, ladder=ladder, train=train, test=test,
                duration=duration)


def _eval(combo):
    """在训练集上评估一组参数，返回 (combo, 训练集汇总)。"""
    params = dict(DEFAULTS)
    params.update(combo)
    res = run_dataset(_CTX["train"], _CTX["strategy"], params, _CTX["ladder"],
                      duration=_CTX["duration"])
    return combo, aggregate(res)


def pareto_front(rows):
    """求 (码率越高越好, 卡顿越低越好) 的 Pareto 前沿。

    rows: [(combo, agg)]。返回不被任何其他点同时支配的点。
    """
    # 先按 (码率, 卡顿) 去重：不同参数常常映射到完全相同的行为，
    # 保留 QoE 最高的那一组，避免前沿被重复点刷屏
    dedup = {}
    for combo, agg in rows:
        key = (round(agg["avg_bitrate_kbps"], 1), round(agg["stall_time_s"], 2))
        if key not in dedup or agg["qoe"] > dedup[key][1]["qoe"]:
            dedup[key] = (combo, agg)
    rows = list(dedup.values())

    front = []
    for combo, agg in rows:
        dominated = False
        for other, o_agg in rows:
            if other is combo:
                continue
            better_br = o_agg["avg_bitrate_kbps"] >= agg["avg_bitrate_kbps"]
            better_stall = o_agg["stall_time_s"] <= agg["stall_time_s"]
            strictly = (
                o_agg["avg_bitrate_kbps"] > agg["avg_bitrate_kbps"]
                or o_agg["stall_time_s"] < agg["stall_time_s"]
            )
            if better_br and better_stall and strictly:
                dominated = True
                break
        if not dominated:
            front.append((combo, agg))
    front.sort(key=lambda x: x[1]["avg_bitrate_kbps"])
    return front


def fmt_combo(combo):
    return " ".join("%s=%g" % (k, combo[k]) for k in sorted(combo))


def main(argv=None):
    ap = argparse.ArgumentParser(description="ABR 参数网格搜索")
    ap.add_argument("--strategy", default="bba", choices=["bba", "mpc"])
    ap.add_argument("--ladder", default="mux", choices=sorted(LADDERS))
    ap.add_argument("--train", default="fcc_hsdpa", help="训练集")
    ap.add_argument("--test", default="fcc_hsdpa_test", help="测试集")
    ap.add_argument("--limit", type=int, default=60,
                    help="每个集合用多少条 trace（控制搜索耗时）")
    ap.add_argument("--duration", type=float, default=120.0,
                    help="每条 trace 仿真时长（秒）")
    ap.add_argument("--trace-scale", type=float, default=1.0,
                    help="trace 吞吐缩放。默认 1.0 时 trace 吞吐(~1.4Mbps)远高于阶梯"
                         "最低档，卡顿只由吞吐归零的断网引起、与选档无关，Pareto 前沿会"
                         "退化成一个点；调小（如 0.3）可让档位真正起约束作用")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--top", type=int, default=8, help="打印 QoE 前 N 组")
    args = ap.parse_args(argv)

    ladder = LADDERS[args.ladder]
    train = load_dataset(args.train, limit=args.limit, scale=args.trace_scale)
    test = load_dataset(args.test, limit=args.limit, scale=args.trace_scale)

    grid = GRID_BBA if args.strategy == "bba" else GRID_MPC
    keys = sorted(grid)
    combos = [dict(zip(keys, v)) for v in itertools.product(*(grid[k] for k in keys))]

    print("策略 %s  阶梯 %s  trace 缩放 %g  训练 %s(%d)  测试 %s(%d)  组合数 %d  jobs %d"
          % (POLICIES[args.strategy].name, args.ladder, args.trace_scale,
             args.train, len(train), args.test, len(test), len(combos), args.jobs))
    print("网格 " + "  ".join("%s=%s" % (k, grid[k]) for k in keys))
    print()

    init_args = (args.strategy, ladder, train, test, args.duration)
    if args.jobs > 1:
        with Pool(args.jobs, initializer=_init, initargs=init_args) as pool:
            rows = pool.map(_eval, combos, chunksize=1)
    else:
        _init(*init_args)
        rows = [_eval(c) for c in combos]

    rows.sort(key=lambda x: -x[1]["qoe"])

    print("== 训练集 QoE 前 %d 组 ==" % args.top)
    print("%-8s %10s %9s %9s  %s" % ("QoE", "码率(kbps)", "卡顿(s)", "切档次数", "参数"))
    for combo, agg in rows[:args.top]:
        print("%-8.3f %10.1f %9.2f %9.2f  %s"
              % (agg["qoe"], agg["avg_bitrate_kbps"], agg["stall_time_s"],
                 agg["switch_count"], fmt_combo(combo)))

    front = pareto_front(rows)
    print()
    print("== Pareto 前沿（码率↑ / 卡顿↓），%d 个点 ==" % len(front))
    print("%10s %9s %9s  %s" % ("码率(kbps)", "卡顿(s)", "QoE", "参数"))
    for combo, agg in front:
        print("%10.1f %9.2f %9.3f  %s"
              % (agg["avg_bitrate_kbps"], agg["stall_time_s"], agg["qoe"],
                 fmt_combo(combo)))

    # 测试集复核：最优组合 vs 当前 Swift 默认参数
    best = rows[0][0]
    default_combo = {k: DEFAULTS[k] for k in keys}
    print()
    print("== 测试集复核（%s）==" % args.test)
    print("%-10s %10s %9s %9s %8s  %s"
          % ("来源", "码率(kbps)", "卡顿(s)", "切档次数", "QoE", "参数"))
    for label, combo in (("默认参数", default_combo), ("搜索最优", best)):
        params = dict(DEFAULTS)
        params.update(combo)
        agg = aggregate(run_dataset(test, args.strategy, params, ladder,
                                    duration=args.duration))
        print("%-10s %10.1f %9.2f %9.2f %8.3f  %s"
              % (label, agg["avg_bitrate_kbps"], agg["stall_time_s"],
                 agg["switch_count"], agg["qoe"], fmt_combo(combo)))

    print()
    print("注：以上为候选参数。写回 Swift 前必须过真机验收"
          "（Network Link Conditioner + 真实 HLS 流），见 spec-calibration.md §5。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
