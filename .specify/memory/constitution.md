# 项目宪法：iOS ABR Player Demo

> 本文件是项目的不可妥协准则，所有下游阶段（spec/plan/tasks/implement）必须遵守。任何冲突按 CRITICAL 处理。
>
> 版本：v2.0（MAJOR：iOS 16+ → 17+，引入 `@Observable` / `SwiftData` / `NavigationStack`；ABREngine 抽成本地 Swift Package；QoS 改为调试 sheet 呈现；新增 XCTest 守"决策逻辑与 Swift 逐行对齐"纪律）

## 1. 技术栈与版本

- 语言：Swift 5.9+
- UI 框架：SwiftUI（禁止用 UIKit + Storyboard）；状态管理用 `@Observable`（iOS 17+），不再用 `ObservableObject` + `@Published`
- 持久化：SwiftData（iOS 17+），用于播放历史与 QoS 采样日志
- 播放器：AVFoundation / AVKit / AVPlayer（禁止用第三方播放器库如 VLCKit、FFmpeg、GSPlayer）
- 最低系统：iOS 17+（需要 `@Observable` / `SwiftData` / `NavigationStack` 现代 API）
- 构建工具：Xcode 15+ / Swift Package Manager
- 禁止引入任何第三方依赖，纯原生实现（SwiftData / `os.Logger` / `AVKit` / `NWPathMonitor` 均为 first-party，不违反此条）
- ABR 算法核心抽成本地 Swift Package `Packages/ABREngine/`，app target 依赖它；算法必须可在不启动 app 的情况下被 XCTest 验证

## 2. 延迟预算（硬红线）

- 首帧耗时 ≤ 2s（BipBop 测试流，WiFi 环境）
- BBA 控制循环周期 = 0.5s（每 500ms 检查一次 buffer 并决策）
- QoS 面板刷新频率 = 2Hz（每 500ms 更新一次显示）
- 切档决策到 AVPlayer 响应延迟 ≤ 1s（AVPlayer 的 `preferredPeakBitRate` 响应时间不可控，但控制循环必须 0.5s 一次）

## 3. ABR 算法约束（核心）

- 必须实现 BBA（Buffer-Based Approach），禁止依赖 AVPlayer 默认 ABR
- BBA 参数（参数选择依据见 README.md「参数选择依据」一节）：
  - reservoir = 5s（buffer 低于此值强制最低档，保不卡顿）—— 依据：AVPlayer 响应延迟 ~1-2s 的安全余量，需大于 segment 时长
  - cushion = 10s（buffer 高于 reservoir + cushion = 15s 可冲最高档）—— 依据：原论文 cushion ≈ reservoir 比例，控制升档平滑度
  - 滞回系数 = 0.8（切档阈值乘以 0.8，避免在边界频繁切档）—— 依据：降档比升档容易 25% 的不对称设计，卡顿代价 > 画质偏低代价
- 控制循环必须记录每次切档决策的完整日志：`{timestamp, from_bitrate, to_bitrate, buffer_seconds, reason}`
- 禁止在 buffer < reservoir 时选非最低档（安全第一，宁可画质差不可卡顿）

## 4. QoS 指标（必须实时显示 7 项）

| 指标 | 数据来源 | 显示格式 |
|---|---|---|
| 当前码率 | `accessLog().events.last?.indicatedBitrate` | `xxx kbps` |
| 观测吞吐 | `accessLog().events.last?.observedBitrate` | `xxx kbps` |
| Buffer 水位 | `loadedTimeRanges` 末尾 - `currentTime` | `xx.x s` |
| 首帧耗时 | 从 `play()` 调用到 `timeControlStatus == .playing` 的时间差 | `xxxx ms` |
| 切档次数 | BBAController 内部计数 | `xx 次` |
| 卡顿次数 | `timeControlStatus == .waitingToPlay` 且 `reasonForWaitingToPlay == .toMinimizeStalls` 的次数 | `xx 次` |
| 当前档位 | BBA 选择的 variant 的 peakBitRate | `xxx kbps (档位 x/N)` |

**呈现方式**：7 项指标必须在 Player 内以可切换的调试 sheet（`QoSDebugSheet`）呈现，不要求常驻主屏。指标本身仍按 0.5s 周期实时更新，只是默认不可见、由用户主动打开。这样既保留 constitution §4 的"实时显示"要求，又符合真实 app 把 QoS 面板藏在调试入口后的惯例。

## 5. 测试纪律

- 必须在 Apple BipBop 多码率测试流上跑通
- 必须用 Network Link Conditioner 验证弱网降档行为（3G profile）
- 禁止用合成数据或 mock 流，必须用真实 HLS 流
- 验收标准：弱网下 buffer 下降→BBA 降档→buffer 恢复→BBA 升档，整个循环可观察
- **ABREngine 必须有 XCTest 守"决策逻辑与 Swift 逐行对齐"纪律**：`Tests/ABREngineTests/` 内用固定合成 trace 喂 `BBAController.decide` / `MPCController.decide`，断言决策序列与 `scripts/simulate_abr.py` 的 `BBAPolicy` / `MPCPolicy` 输出逐拍一致。改 `simulate_abr.py` 的策略逻辑时必须同步重生成期望值，Swift 测试必须能独立于 app 跑通。

## 6. 代码治理

- 所有 KVO 观察必须在 deinit 时反注册（避免内存泄漏）
- 所有 Timer 必须在 viewWillDisappear / deinit 时 invalidate
- AVPlayerItem 必须在替换源时清理旧的观察者
- 禁止 force unwrap（`!`），除非确认非 nil（如 `variants.first!` 在 variants 已排序且非空时可用）
- 所有公开类型必须有文档注释（`///`）
- ABR 算法参数（reservoir/cushion/hysteresis/代价权重）不得硬编码在控制器内，必须由 `ABRConfig` struct 注入，便于 Settings 调整与离线搜参结果写回

## 7. SPDD 流程纪律

- constitution 是不可妥协的，spec/plan/tasks 任何与之冲突的地方标 CRITICAL
- spec 必须先于 plan，plan 必须先于 tasks，tasks 必须先于 implement
- implement 阶段发现 spec 不可行时，必须回 spec 修改，不能直接绕过
- 每次修改 constitution 必须 MAJOR 版本 +1
