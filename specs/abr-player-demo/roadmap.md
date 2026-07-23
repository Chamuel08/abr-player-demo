# Roadmap：iOS ABR Player Demo 技术演进路线

> 状态：规划中（Vision）
>
> 本文件描述 `abr-player-demo` 从当前 BBA 基线到 BBA + 吞吐预测、再到 BBA + MPC 闭环的持续迭代路径。

## 当前阶段：MVP + BBA（已完成）

- 播放 Apple BipBop HLS 流
- 自定义 BBA（Buffer-Based Approach）ABR 算法
- 实时 QoS 面板（7 项指标）
- 切档日志 + 模拟弱网开关
- SPDD 四件套文档（constitution / spec / plan / tasks）

## 阶段一：BBA + 吞吐预测（下一迭代）

目标：在 BBA 的 buffer 基础上，引入轻量带宽预测，让降档更前置、升档更积极。

### 控制变量
- 在 BBA 决策前，增加一个"带宽安全校验"：
  - 若当前目标码率 > 1.2 × 观测吞吐（observedBitrate），则临时降低目标码率到安全档位
  - 若观测吞吐 > 1.5 × 当前目标码率且 buffer 充足，可提前升档
- 保留 BBA 的 reservoir/cushion 作为安全兜底

### 预测模型（轻量）
- 用指数加权移动平均（EWMA）估计近期吞吐：
  ```
  throughput_ema = α * current_observed + (1-α) * throughput_ema
  ```
  - 建议 α = 0.3，对抖动有一定平滑
- 不使用复杂时间序列模型，保持端侧低算力

### 验证标准
- 弱网场景下，buffer 下降到 reservoir 之前的切档次数减少
- 正常网络下，升档速度不劣化
- QoS 面板新增"预测吞吐"字段

## 阶段二：BBA + MPC（远期迭代）

目标：把 ABR 策略参数和码率序列选择建模为 Model Predictive Control（MPC）问题，实现数据驱动的自动优化。

### 为什么用 MPC
- ABR 本质上是**序列决策**：当前选档会影响未来 buffer、卡顿、画质
- 传统 BBA 只考虑当前状态，MPC 可以预测未来数秒的状态演化并做滚动优化
- 在 iOS 端侧，MPC 可以兼顾：不卡顿（安全约束）、画质最高（目标）、切换少（稳定性）、能耗低（可选）

### 状态变量 x(t)

```
x(t) = [
  buffer_seconds,           # 当前 buffer 水位
  current_bitrate,          # 当前播放码率
  observed_bitrate,        # 最近观测吞吐
  estimated_throughput,    # EWMA 预测吞吐
  stall_count,             # 已发生卡顿次数
  switch_count,            # 已发生切档次数
  playback_time            # 当前播放时刻
]
```

### 控制变量 u(t)

| 变量 | 含义 | 当前值 | 可调范围 |
|---|---|---|---|
| `reservoir` | 安全 buffer 下限 | 5.0 s | [3.0, 8.0] |
| `cushion` | 升档 buffer 区间 | 10.0 s | [6.0, 15.0] |
| `hysteresis` | 滞回系数 | 0.8 | [0.6, 0.95] |
| `target_bitrate` | 下一决策周期的目标码率 | 由 BBA 决定 | [min_variant, max_variant] |

### 预测模型

在每个控制窗口内（如未来 5 秒，预测步长 0.5 秒），用简化模型推演：

```
buffer(t+1) = buffer(t) + 0.5 * (download_rate / target_bitrate - 1.0)
```

- `download_rate`：用观测吞吐或预测吞吐近似
- 若 `buffer(t+1) < 0`：计为一次卡顿
- 若 `target_bitrate` 变化：计为一次切档

### 代价函数 J

```
J(u) = Σ_t [
    w_stall     * stall_penalty(t)        # 卡顿高代价
  + w_quality  * (max_bitrate - target_bitrate(t)) / max_bitrate  # 画质损失
  + w_switch   * switch_indicator(t)      # 频繁切档惩罚
  + w_compute  * vlm_calls_or_complexity  # 可选：计算能耗
]
```

权重建议：
- `w_stall`：100（卡顿零容忍）
- `w_quality`：10（画质优化）
- `w_switch`：5（避免抖动）
- `w_compute`：1（端侧能耗）

### 滚动优化

在每个控制周期（0.5s）求解：

```
u*(t) = argmin_{u ∈ U} J(u) over horizon H
```

- 预测时域 H = 10 步（5 秒）
- 只应用第一个控制动作 `u*(t)`，下一周期重新观测并优化
- 求解方式：由于控制变量离散（档位有限），可用穷举搜索或 beam search，计算量可控

### 与 BBA 的 hybrid 融合

- MPC 负责"正常网络下的画质优化"和"参数自动校准"
- BBA 负责"安全兜底"：当 buffer < reservoir 或预测模型失效时，强制最低档
- 这样即使 MPC 预测不准，也不会导致卡顿

## 阶段三：离线参数校准（持续）

- 用模拟器/真机录制不同网络条件下的 QoS 日志（buffer、码率、卡顿、切档）
- 用 Network Link Conditioner 或自定义弱网环境回放日志
- 对每一组 `(reservoir, cushion, hysteresis, w_stall, w_quality, w_switch)` 做网格搜索
- 选择 Pareto 最优的参数组合，更新到 `BBAController.swift` 或 MPC 配置

## 数据收集

为支持 MPC 和参数校准，QoS 面板需要增加持久化：

- 在真机测试时，把每 0.5s 的 `(timestamp, buffer, current_bitrate, observed_bitrate, target_bitrate, switch_count, stall_count)` 写入本地 CSV
- 提供 `scripts/analyze_qos_logs.py` 做回放与可视化
- 这些日志是 MPC 训练/校准的数据来源

## 验收标准

| 阶段 | 标准 |
|---|---|
| 阶段一 | 吞吐预测的 EWMA 平滑后，弱网场景卡顿次数 ≤ BBA 基线 |
| 阶段二 | MPC 在正常网络下画质档位 ≥ BBA 基线，且卡顿次数 ≤ BBA 基线 |
| 阶段三 | 能自动搜索出一组 Pareto 最优参数，并更新到代码中 |

## 相关文档

- [项目 README](../../README.md#技术演进路线与持续迭代)
- [BBA 算法说明](../../README.md#bba-算法说明)
- [constitution（约束与纪律）](../../.specify/memory/constitution.md)
