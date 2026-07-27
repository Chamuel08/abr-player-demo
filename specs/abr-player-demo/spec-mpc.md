# Spec 增量：BBA + 吞吐预测 + MPC

> 本文件是相对 `spec.md` 的增量需求，对应 roadmap 阶段一（吞吐预测）与阶段二（MPC）。
> 与 constitution 冲突之处以 constitution 为准（CRITICAL）。本增量不修改任何 constitution 红线。

## 1. 目标

在现有 BBA 基线之上，新增两种可选 ABR 策略，并在 UI 中可切换、可对比：

- **BBA**（已有，保留为安全基线）
- **MPC**（Model Predictive Control，滚动时域优化）

吞吐预测（EWMA）作为 MPC 的状态输入，同时作为独立 QoS 指标展示。

## 2. 用户故事

- 作为播放器开发者，我想在 UI 切换 BBA / MPC 策略，以对比两种算法在同一流上的 QoS 表现。
- 作为播放器开发者，我想看到"预测吞吐"和"累计代价 J"，以判断 MPC 是否在画质与卡顿之间做了更优权衡。

## 3. 功能需求

### 3.1 ABR 策略抽象

- 新增 `ABRController` 协议，统一 BBA 与 MPC 的对外接口：`start()` / `stop()` / `currentTarget` / `switchCount` / `simulateWeakNetwork` / `onSwitch`。
- `BBAController` 与 `MPCController` 均遵循该协议。
- `ABRPlayerController` 持有一个 `ABRController?`，并暴露 `@Published strategy: ABRStrategy`，切换时拆除旧控制器、用相同 variants 构造新控制器。

### 3.2 吞吐预测（EWMA）

- 新增 `ThroughputEstimator`：用 EWMA 平滑 `observedBitrate`，`α = 0.3`。
- 提供 `feed(observed:)` 与 `current: Double`（bps）。
- 无观测时返回 0，调用方需处理 0 的情况。

### 3.3 MPC 控制器

- 状态：`buffer_seconds`、`current_bitrate`、`observed_bitrate`、`estimated_throughput`。
- 预测模型：`buffer(t+1) = buffer(t) + dt * (throughput / target_bitrate - 1)`。
- **时域粒度：按 segment 推进**，`dt = segment 时长 = 4s`，`H = 5`（20 秒窗口），对齐 FastMPC/RobustMPC（Yin et al. SIGCOMM '15）的标准形式。
  - CRITICAL：`H * dt` 必须显著大于 `reservoir`。否则 rollout 推演到时域末尾 buffer 还没跌破 0，`stall_penalty` 恒为 0，MPC 看不见卡顿风险、只会一味冲最高档。初版取 `dt = 0.5s, H = 10`（窗口 5s ≈ reservoir）即踩此坑，由离线仿真发现并修正，见 [spec-calibration.md](spec-calibration.md) §6。
- 代价函数：
  `J = Σ_t [ w_stall * stall_seconds + w_quality * dt * (max - target)/max ] + w_switch * switch_indicator`
  - `w_stall = 100`，`w_quality = 10`，`w_switch = 5`
  - `stall_seconds`：预测 buffer 跌破 0 时，按线性插值折算的见底秒数（**不是计 1 次**）
  - `switch_indicator`：候选档位 ≠ 当前档位计 1
  - CRITICAL：卡顿与画质均按"每秒"计，量纲不得依赖 `dt`。若按"步数"计，改 `dt` 会同时改变卡顿与画质的相对权重，参数搜索结论失效。
- 求解：对每个候选下一档位，用"保持该档位"策略滚动展开时域，取总代价最小的候选作为本周期动作（one-step optimization + hold rollout）。
- **安全兜底（不可妥协）**：当 `buffer < reservoir` 或 `simulateWeakNetwork` 或 `estimated_throughput <= 0` 时，强制最低档，跳过 MPC 优化。
- **节奏解耦**：rollout 只在 segment 边界（播放时间推进满 `segmentDuration`）重算；安全兜底仍每 `controlLoopInterval = 0.5s` 检查。未到边界且已有目标档位时维持不变。
  - 理由：若安全兜底也降到 4s 一次，`buffer < reservoir` 的降档反应会慢 4 倍，等于拿卡顿换切档平稳。
  - seek 导致播放时间回退时重置边界计时。
- 切档日志复用 `SwitchLog`，reason 标注 `MPC` 前缀。

### 3.4 QoS 面板扩展

- `QoSMetrics` 新增：`estimatedThroughput: Double`（bps）、`cumulativeCost: Double`。
- `QoSDashboard` 新增显示：预测吞吐、累计代价、当前策略。
- 不删除原有 7 项指标。

## 4. 非功能需求

- MPC rollout 每 segment（4s）重算一次，安全兜底每 0.5s 检查一次；单次求解 ≤ 1ms 量级（候选数 × 时域，纯算术）。
- 不引入任何第三方依赖。
- 切换策略时不中断播放，variants 复用已解析结果。

## 5. 验收标准

- BBA 策略下行为与现状一致（回归不劣化）。
- MPC 策略下：正常网络画质档位 ≥ BBA 同期；弱网（模拟弱网开关）强制最低档，0 卡顿。
- QoS 面板显示预测吞吐与累计代价，且数值随播放实时变化。
- 切换 BBA↔MPC 不崩溃、不中断播放。
