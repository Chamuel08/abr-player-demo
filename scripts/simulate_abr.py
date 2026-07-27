#!/usr/bin/env python3
"""ABR 离线仿真器：用真实网络 trace 驱动 BBA / MPC 决策，输出 QoS 指标。

设计约束（见 specs/abr-player-demo/spec-calibration.md）：

1. 决策逻辑与 Swift 实现逐行对齐。`BBAPolicy` 对应 BBAController.decide/quantize，
   `MPCPolicy` 对应 MPCController.decide/rolloutCost，包含同样的三种安全兜底。
   两边不一致时以 Swift 为准，修仿真器。
2. 控制周期 dt=0.5s，与 Swift 的 controlLoopInterval 一致（不是按 segment 决策）。
3. buffer 动力学由"下载进度 + 播放消耗"真实推演，不复用 MPC 的预测模型，
   否则 MPC 会在自己的假设里自证。
4. 纯标准库，无第三方依赖；同一 trace 重复运行结果完全一致（无随机）。

用法：
    python3 scripts/simulate_abr.py --dataset norway_3g --strategy both
    python3 scripts/simulate_abr.py --dataset fcc_hsdpa_test --strategy mpc --limit 50
"""

import argparse
import os
import sys
from bisect import bisect_right

# ---------------------------------------------------------------- 常量

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRACE_ROOT = os.path.join(ROOT, "data", "traces")

# 数据集别名 -> trace 目录
DATASETS = {
    "norway_3g": "cooked_3gp",
    "fcc": "fcc_ori/cooked_traces",
    "fcc_hsdpa": "fcc_and_hsdpa/cooked_traces",
    "fcc_hsdpa_test": "fcc_and_hsdpa/cooked_test_traces",
    "oboe": "traces_oboe",
    "puffer_2021": "puffer_211017/cooked_traces",
    "puffer_2022": "puffer_220218/cooked_traces",
}

# 码率阶梯（bps）。默认用 Mux x36xhzz 测试流的 5 档：档位跨度 25 倍，
# 比 BipBop（41k~1928k）更能区分 ABR 策略差异。
LADDER_MUX = [246440.0, 460560.0, 836280.0, 2149280.0, 6221600.0]
# Apple BipBop 档位，与当前 iOS demo 里跑的流一致
LADDER_BIPBOP = [41457.0, 232370.0, 649879.0, 991714.0, 1927833.0]
LADDERS = {"mux": LADDER_MUX, "bipbop": LADDER_BIPBOP}

# 仿真参数
DT = 0.5           # 控制周期（秒），与 Swift controlLoopInterval 一致
SEGMENT_SEC = 4.0  # 单个 segment 时长（秒）
BUFFER_CAP = 60.0  # buffer 上限（秒），满了就不再下载

# QoE 线性加权（Pensieve/MPC 论文的经典形式）
QOE_STALL_PENALTY = 4.3   # 每秒卡顿的惩罚（等价于 4.3 Mbps 画质）
QOE_SWITCH_PENALTY = 1.0  # 每次切档的惩罚（按码率差 Mbps 计）

# 默认 ABR 参数（与 Swift 默认值一致）
DEFAULTS = {
    "reservoir": 5.0,
    "cushion": 10.0,
    "hysteresis": 0.8,
    "w_stall": 100.0,
    "w_quality": 10.0,
    "w_switch": 5.0,
    "alpha": 0.3,      # EWMA 平滑系数
    "mpc_dt": 4.0,     # MPC 预测步长 = segment 时长（秒）
    "horizon": 5.0,    # MPC 预测步数（H=5 × 4s = 20s 窗口）
}


# ---------------------------------------------------------------- trace 加载


class Trace:
    """一条吞吐 trace，格式为 [时间戳(秒), 吞吐(Mbit/s)]。

    提供 throughput_at(t)：阶梯保持（zero-order hold）取值，超出末尾则循环回放，
    这样短 trace 也能撑满整段仿真。
    """

    def __init__(self, name, times, mbps, scale=1.0):
        self.name = name
        self.times = times
        # 转成 bps，并应用缩放（用于适配不同档位跨度的码率阶梯）
        self.bps = [m * 1e6 * scale for m in mbps]
        self.duration = times[-1] if times else 0.0

    def throughput_at(self, t):
        if not self.times:
            return 0.0
        # 循环回放
        if self.duration > 0:
            t = t % self.duration
        idx = bisect_right(self.times, t) - 1
        if idx < 0:
            idx = 0
        return self.bps[idx]


def load_trace(path, scale=1.0):
    """读取单条 trace，跳过格式异常行。返回 Trace 或 None（有效点 < 2 时）。"""
    times, mbps = [], []
    try:
        with open(path, "r", errors="replace") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 2:
                    continue
                try:
                    t, m = float(parts[0]), float(parts[1])
                except ValueError:
                    continue
                # FCC / Puffer 里存在吞吐恰好为 0 的采样点，保留（真实的网络中断），
                # 但下游除法必须防零。
                if t < 0 or m < 0:
                    continue
                times.append(t)
                mbps.append(m)
    except OSError:
        return None
    if len(times) < 2:
        return None
    return Trace(os.path.basename(path), times, mbps, scale=scale)


def load_dataset(dataset, limit=None, scale=1.0):
    """加载数据集下的全部 trace，按文件名排序保证确定性。"""
    if dataset not in DATASETS:
        raise SystemExit(
            "未知数据集 %r，可选：%s" % (dataset, ", ".join(sorted(DATASETS)))
        )
    d = os.path.join(TRACE_ROOT, DATASETS[dataset])
    if not os.path.isdir(d):
        raise SystemExit(
            "trace 目录不存在：%s\n请先运行 scripts/download_traces.sh" % d
        )
    files = sorted(
        os.path.join(d, f)
        for f in os.listdir(d)
        if os.path.isfile(os.path.join(d, f))
    )
    if limit:
        files = files[:limit]
    traces = [t for t in (load_trace(p, scale) for p in files) if t]
    if not traces:
        raise SystemExit("数据集 %s 没有可用 trace" % dataset)
    return traces


# ---------------------------------------------------------------- BBA 策略


class BBAPolicy:
    """对应 ABR/BBAController.swift 的 decide() + quantize()。

    三段决策：buffer < reservoir 强制最低档；buffer > reservoir+cushion 冲最高档；
    中间线性插值后做滞回量化（升档保守、降档激进）。
    """

    name = "BBA"

    def __init__(self, ladder, params):
        self.ladder = sorted(ladder)
        self.reservoir = params["reservoir"]
        self.cushion = params["cushion"]
        self.hysteresis = params["hysteresis"]
        self.current_target = None  # 对应 Swift 的 currentTarget（初始 nil）

    def decide(self, buffer_sec, observed_bps, weak_network=False, now=0.0):
        min_br, max_br = self.ladder[0], self.ladder[-1]
        if weak_network:
            return min_br
        if buffer_sec < self.reservoir:
            return min_br
        if buffer_sec > self.reservoir + self.cushion:
            return max_br
        ratio = (buffer_sec - self.reservoir) / self.cushion
        raw = min_br + ratio * (max_br - min_br)
        return self._quantize(raw)

    def _quantize(self, raw):
        # 选第一个 >= raw 的档位，否则最高档（与 Swift 的循环写法等价）
        candidate_index = 0
        for i, br in enumerate(self.ladder):
            candidate_index = i
            if br >= raw:
                break
        candidate = self.ladder[candidate_index]

        cur = self.current_target
        if cur is not None and cur in self.ladder:
            if candidate > cur:
                # 升档保守：raw 没超过候选档位 * hysteresis 就保持
                if raw < candidate * self.hysteresis:
                    return cur
            elif candidate < cur:
                # 降档激进：raw 没低于候选档位 / hysteresis 就保持
                if raw > candidate / self.hysteresis:
                    return cur
        return candidate

    def commit(self, target):
        """决策被应用后更新内部状态（Swift 中在切档分支里赋值 currentTarget）。"""
        self.current_target = target


# ---------------------------------------------------------------- MPC 策略


class MPCPolicy:
    """对应 ABR/MPCController.swift 的 decide() + rolloutCost()。

    安全兜底（弱网 / buffer<reservoir / 无吞吐观测）优先，其余情况对每个候选档位
    做"保持该档位"的时域展开，取总代价最小者。
    """

    name = "MPC"

    def __init__(self, ladder, params):
        self.ladder = sorted(ladder)
        self.reservoir = params["reservoir"]
        self.cushion = params["cushion"]
        self.hysteresis = params["hysteresis"]
        self.w_stall = params["w_stall"]
        self.w_quality = params["w_quality"]
        self.w_switch = params["w_switch"]
        self.alpha = params["alpha"]
        # 预测按 segment 推进（dt=4s, H=5 → 20s 窗口），对齐 Swift MPCController。
        # 窗口必须显著大于 reservoir，否则 rollout 里 buffer 推不到 0，卡顿项恒为 0。
        self.dt = params["mpc_dt"]
        self.horizon = int(params["horizon"])
        self.segment_duration = params["mpc_dt"]
        self.last_rollout_time = None  # 上次 rollout 的播放时刻
        self.current_target = None
        self.estimated_throughput = 0.0  # EWMA
        self.cumulative_cost = 0.0

    def _should_recompute(self, now):
        """segment 边界判定，对应 Swift shouldRecomputeRollout()。"""
        last = self.last_rollout_time
        if last is None or now < last or now - last >= self.segment_duration:
            self.last_rollout_time = now
            return True
        return False

    def decide(self, buffer_sec, observed_bps, weak_network=False, now=0.0):
        # EWMA 吞吐预测，对应 ThroughputEstimator.feed()
        if observed_bps > 0:
            if self.estimated_throughput <= 0:
                self.estimated_throughput = observed_bps
            else:
                self.estimated_throughput = (
                    self.alpha * observed_bps
                    + (1 - self.alpha) * self.estimated_throughput
                )

        min_br, max_br = self.ladder[0], self.ladder[-1]
        # 安全兜底（与 BBA 一致，不可妥协）。每个控制周期都查，不等 segment 边界。
        if weak_network:
            return min_br
        if buffer_sec < self.reservoir:
            return min_br
        if self.estimated_throughput <= 0:
            return min_br

        # 未到 segment 边界：维持当前档位，不重算 rollout
        due = self._should_recompute(now)
        if not due and self.current_target is not None:
            return self.current_target

        current_br = self.current_target if self.current_target is not None else min_br
        best_br, best_cost = min_br, float("inf")
        for candidate in self.ladder:
            cost = self._rollout_cost(
                candidate, current_br, buffer_sec, self.estimated_throughput, max_br
            )
            if cost < best_cost:
                best_cost, best_br = cost, candidate
        self.cumulative_cost += best_cost
        return best_br

    def _rollout_cost(self, candidate, current_br, buffer_sec, throughput, max_br):
        buf = buffer_sec
        stall_seconds = 0.0
        cost = 0.0
        if candidate != current_br:
            cost += self.w_switch
        for _ in range(self.horizon):
            drain_rate = throughput / candidate
            nxt = buf + self.dt * (drain_rate - 1.0)
            if nxt < 0:
                # 中途见底：按线性插值折算卡顿秒数，惩罚量纲不依赖 dt
                stall_seconds += -nxt
                buf = 0.0
            else:
                buf = nxt
            cost += self.w_quality * self.dt * (max_br - candidate) / max_br
        cost += self.w_stall * stall_seconds
        return cost

    def commit(self, target):
        self.current_target = target


POLICIES = {"bba": BBAPolicy, "mpc": MPCPolicy}


# ---------------------------------------------------------------- 仿真引擎


class Result:
    """单条 trace 的仿真结果。"""

    def __init__(self, trace_name, policy_name):
        self.trace = trace_name
        self.policy = policy_name
        self.play_time = 0.0        # 实际播放时长（秒）
        self.startup_time = 0.0     # 首帧耗时（起播前的 buffer 填充，不算卡顿）
        self.stall_time = 0.0       # 累计卡顿时长（秒），不含 startup
        self.stall_count = 0        # 卡顿次数（连续卡顿算 1 次）
        self.switch_count = 0       # 切档次数
        self.switch_magnitude = 0.0 # 切档码率差之和（bps）
        self.bitrate_time = 0.0     # ∫ 码率 dt，用于算时间加权平均码率

    @property
    def avg_bitrate(self):
        return self.bitrate_time / self.play_time if self.play_time > 0 else 0.0

    @property
    def qoe(self):
        """线性 QoE（Mbps 量纲）：画质 - 卡顿惩罚 - 切档惩罚。

        除以 play_time 做归一化，让不同长度的 trace 可比。
        """
        if self.play_time <= 0:
            return 0.0
        quality = self.avg_bitrate / 1e6
        stall = QOE_STALL_PENALTY * self.stall_time / self.play_time
        switch = QOE_SWITCH_PENALTY * (self.switch_magnitude / 1e6) / self.play_time
        return quality - stall - switch


def simulate(trace, policy, duration=None, weak_network=False):
    """在一条 trace 上跑一次仿真。

    buffer 动力学：每个 dt 内，按当前 trace 吞吐下载 target 码率的数据，
    下载到的秒数入 buffer，同时播放消耗 dt 秒。buffer 见底则卡顿（播放停住，
    但下载继续）。这是真实推演，与 MPC 内部的预测模型无关。
    """
    res = Result(trace.name, policy.name)
    sim_duration = duration if duration else min(trace.duration, 300.0)

    buffer_sec = 0.0
    target = policy.ladder[0]
    started = False      # 是否已起播；起播前的等待记为 startup_time 而非卡顿
    was_stalling = False
    t = 0.0

    while t < sim_duration:
        # ---- 控制循环：每 dt 决策一次（对应 Swift Timer 0.5s）
        observed = trace.throughput_at(t)
        new_target = policy.decide(buffer_sec, observed,
                                   weak_network=weak_network, now=t)
        if new_target != target:
            res.switch_count += 1
            res.switch_magnitude += abs(new_target - target)
            target = new_target
        policy.commit(target)

        # ---- 下载：dt 时间内按吞吐下载，换算成 buffer 秒数
        # 防零：吞吐为 0（真实网络中断）时下载不到任何数据
        if target > 0 and observed > 0 and buffer_sec < BUFFER_CAP:
            downloaded_bits = observed * DT
            buffer_sec += downloaded_bits / target
            buffer_sec = min(buffer_sec, BUFFER_CAP)

        # ---- 播放：消耗 dt 秒 buffer；不足则卡顿
        if buffer_sec >= DT:
            buffer_sec -= DT
            res.play_time += DT
            res.bitrate_time += target * DT
            started = True
            was_stalling = False
        else:
            # buffer 里剩下的还能播一点，其余时间是等待
            playable = buffer_sec
            if playable > 0:
                res.play_time += playable
                res.bitrate_time += target * playable
                started = True
            waited = DT - playable
            if started:
                # 起播后再等待才是卡顿（rebuffer）
                res.stall_time += waited
                if not was_stalling:
                    res.stall_count += 1
                was_stalling = True
            else:
                # 起播前的 buffer 填充是首帧耗时，不计卡顿
                res.startup_time += waited
            buffer_sec = 0.0

        t += DT

    return res


def run_dataset(traces, strategy, params, ladder, duration=None, weak_network=False):
    """在整个数据集上跑仿真，返回逐 trace 结果。"""
    cls = POLICIES[strategy]
    out = []
    for tr in traces:
        policy = cls(ladder, params)  # 每条 trace 用全新策略实例，状态不串
        out.append(simulate(tr, policy, duration=duration, weak_network=weak_network))
    return out


def aggregate(results):
    """汇总多条 trace 的结果为平均值。"""
    n = len(results)
    if n == 0:
        return {}
    return {
        "traces": n,
        "avg_bitrate_kbps": sum(r.avg_bitrate for r in results) / n / 1e3,
        "startup_time_s": sum(r.startup_time for r in results) / n,
        "stall_time_s": sum(r.stall_time for r in results) / n,
        "stall_count": sum(r.stall_count for r in results) / n,
        "switch_count": sum(r.switch_count for r in results) / n,
        "qoe": sum(r.qoe for r in results) / n,
    }


# ---------------------------------------------------------------- CLI


def format_row(label, agg):
    return "%-6s %6d  %10.1f  %8.2f  %9.2f  %8.2f  %9.2f  %8.3f" % (
        label,
        agg["traces"],
        agg["avg_bitrate_kbps"],
        agg["startup_time_s"],
        agg["stall_time_s"],
        agg["stall_count"],
        agg["switch_count"],
        agg["qoe"],
    )


HEADER = "%-6s %6s  %10s  %8s  %9s  %8s  %9s  %8s" % (
    "策略", "traces", "码率(kbps)", "首帧(s)", "卡顿(s)", "卡顿次数", "切档次数", "QoE",
)


def build_params(args):
    p = dict(DEFAULTS)
    for k in p:
        v = getattr(args, k, None)
        if v is not None:
            p[k] = v
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="ABR 离线仿真器（BBA / MPC）",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--dataset", default="norway_3g",
                    help="数据集：" + ", ".join(sorted(DATASETS)))
    ap.add_argument("--strategy", default="both", choices=["bba", "mpc", "both"])
    ap.add_argument("--ladder", default="mux", choices=sorted(LADDERS),
                    help="码率阶梯：mux(246k~6222k) / bipbop(41k~1928k)")
    ap.add_argument("--limit", type=int, default=None, help="只跑前 N 条 trace")
    ap.add_argument("--duration", type=float, default=None,
                    help="每条 trace 仿真时长（秒），默认 min(trace 时长, 300)")
    ap.add_argument("--trace-scale", type=float, default=1.0,
                    help="trace 吞吐缩放系数，用于适配档位跨度")
    ap.add_argument("--weak-network", action="store_true",
                    help="模拟弱网开关（强制最低档，验证安全兜底）")
    ap.add_argument("--per-trace", action="store_true", help="打印逐 trace 明细")
    for k, v in DEFAULTS.items():
        ap.add_argument("--" + k.replace("_", "-"), dest=k, type=float, default=None,
                        help="默认 %s" % v)
    args = ap.parse_args(argv)

    params = build_params(args)
    ladder = LADDERS[args.ladder]
    traces = load_dataset(args.dataset, limit=args.limit, scale=args.trace_scale)

    print("数据集 %s（%d 条 trace）  阶梯 %s（%.0f~%.0f kbps）  弱网=%s"
          % (args.dataset, len(traces), args.ladder,
             ladder[0] / 1e3, ladder[-1] / 1e3, args.weak_network))
    print("参数 " + "  ".join("%s=%g" % (k, params[k]) for k in sorted(params)))
    print()
    print(HEADER)

    strategies = ["bba", "mpc"] if args.strategy == "both" else [args.strategy]
    for s in strategies:
        results = run_dataset(traces, s, params, ladder,
                              duration=args.duration,
                              weak_network=args.weak_network)
        print(format_row(POLICIES[s].name, aggregate(results)))
        if args.per_trace:
            for r in results:
                print("       %-44s %8.1f kbps  stall %5.1fs  sw %3d"
                      % (r.trace[:44], r.avg_bitrate / 1e3, r.stall_time,
                         r.switch_count))
    return 0


if __name__ == "__main__":
    sys.exit(main())
