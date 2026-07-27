# Spec 增量：离线参数校准（roadmap 阶段三）

> 本文件是相对 `spec.md` / `spec-mpc.md` 的增量需求，对应 roadmap 阶段三。
> 与 constitution 冲突之处以 constitution 为准（CRITICAL）。本增量不修改任何 constitution 红线。

## 1. 目标

把 BBA / MPC 的参数从"工程经验取值"升级为"在公开真实网络 trace 上搜出来的取值"，并给出可复现的搜索过程。

核心矛盾：constitution §5 要求"禁止 mock 流，必须用真实 HLS 流"，但几千组参数 × 每组数百秒的真机回放不可行。
解法是**两层验证**，两层各自的职责边界必须写清楚：

| 层 | 载体 | 数据 | 职责 |
|---|---|---|---|
| 离线仿真层 | Python（`scripts/`） | 公开真实吞吐 trace | 大规模搜参，产出候选参数与 Pareto 前沿 |
| 真机验收层 | iOS（Xcode） | 真实 HLS 流 + Network Link Conditioner | 只验证 2~3 组候选参数，确认仿真结论在真实 AVPlayer 上成立 |

**离线仿真层不替代 constitution §5 的真机验收**，它只负责缩小搜索空间。任何参数变更进入 `BBAController.swift` / `MPCController.swift` 之前，必须过真机验收层。

## 2. 用户故事

- 作为播放器开发者，我想在几百条真实网络 trace 上批量比较 BBA 与 MPC，而不是靠几次手动观察下结论。
- 作为播放器开发者，我想知道 `(reservoir, cushion, hysteresis)` 改动会把"画质 / 卡顿"权衡推向哪一侧，并看到 Pareto 前沿。
- 作为项目评审者，我想只跑一条命令就复现出参数结论。

## 3. 功能需求

### 3.1 数据集获取

- 新增 `scripts/download_traces.sh`，拉取公开吞吐 trace 到 `data/traces/`。
- 数据集**不入库**（`.gitignore` 排除 `data/`），仓库只保留下载脚本，保持仓库轻量。
- trace 统一格式：两列 `时间戳(秒) \t 吞吐(Mbit/s)`。

### 3.2 ABR 仿真器

- 新增 `scripts/simulate_abr.py`，用 trace 驱动 BBA / MPC 决策，输出 QoS 指标。
- **决策逻辑必须与 Swift 实现逐行对齐**（同样的 reservoir/cushion/hysteresis 三段决策、同样的滞回量化、同样的 MPC rollout 代价与三种安全兜底）。仿真器与 Swift 不一致时，以 Swift 为准并修仿真器。
- 控制周期 `dt = 0.5s`，与 Swift 的 `controlLoopInterval` 一致（不是按 segment 决策）。
- buffer 动力学由"下载进度 + 播放消耗"真实推演，不复用 MPC 内部的预测模型（否则 MPC 会在自己的假设里自证）。
- 输出指标：平均码率、卡顿时长、卡顿次数、切档次数、QoE（线性加权）。

### 3.3 参数网格搜索

- 新增 `scripts/grid_search.py`，对参数组合做网格搜索。
- 必须使用**训练集搜参、测试集报数**（`fcc_and_hsdpa/cooked_traces` 搜、`cooked_test_traces` 报），避免过拟合。
- 输出 QoE 最优参数 + `(平均码率, 卡顿时长)` 的 Pareto 前沿。

## 4. 非功能需求

- 纯 Python 标准库，不引入 numpy / pandas 等依赖（与"无第三方依赖"的项目风格一致）。
- 网格搜索支持 `--jobs` 多进程，全量搜索在普通笔记本上 ≤ 10 分钟。
- 仿真器可指定码率阶梯与 trace 缩放，以适配不同档位跨度的测试流。

## 5. 验收标准

- 一条命令可复现：`scripts/download_traces.sh && python3 scripts/grid_search.py`。
- 仿真器在同一 trace 上重复运行结果完全一致（确定性，无随机）。
- 弱网 trace（Norway 3G）上，MPC 的卡顿时长 ≤ BBA（对应 roadmap 阶段二验收标准）。
- 网格搜索能产出 Pareto 前沿，且 QoE 最优参数在测试集上不劣于当前默认参数。
- **参数结论未经真机验收前，不写回 Swift 代码**。

## 6. 本层发现并修正的实现缺陷：MPC 时域粒度

离线层的第一个实质产出不是参数值，而是发现 `MPCController` 的时域粒度选错了。

**现象**：测试集上 MPC 卡顿 10.37s 略高于 BBA 的 10.33s，不满足 roadmap 阶段二验收标准；同时码率虚高到 2498 kbps（BBA 562）、切档 118.9 次（BBA 41.8），QoE -4.693 远差于 BBA 的 -0.826。

**根因**：初版按控制周期推进预测（`dt = 0.5s`，`H = 10`），预测窗口仅 5s ≈ `reservoir`。而 MPC 只在 `buffer ≥ reservoir` 时启用，rollout 从 5s 起步往前推 5s，即使一路下跌也刚好在时域末尾摸到 0 —— `stall_penalty` 恒为 0。代价函数里卡顿项失效后只剩画质项和切档项，MPC 就只管冲最高档。

**修正**：对齐 FastMPC/RobustMPC（Yin et al. SIGCOMM '15）的标准形式，改为按 segment 决策：`dt = segment 时长 = 4s`，`H = 5`，窗口 20s 远超 reservoir。配套改两处以免粒度切换引入新失真：卡顿惩罚按秒计（线性插值折算见底秒数）而非按步数计；rollout 与安全兜底的节奏解耦。

**结果**：卡顿 10.26s < BBA 10.33s，切档 15.0（-64%），QoE -0.791 > -0.826，验收通过。窗口扫描（`dt=4s` 固定）显示窗口 ≤ 8s 时卡顿项基本失效，跨过 12s 后行为才稳定。

**沉淀为判据**：`horizon × dt` 必须显著大于 `reservoir`。已写入 [spec-mpc.md](spec-mpc.md) §3.3 的 CRITICAL 标注。

这条记录也划清了两层的关系：离线层不只是"给参数调值"，它是**验证实现是否符合设计意图的手段**。真机上"看着正常"的实现，在几百条 trace 的统计口径下才暴露出代价函数有一项是死的。
