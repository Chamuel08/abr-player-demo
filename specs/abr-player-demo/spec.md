# Spec：iOS ABR Player Demo

> 基于 `.specify/memory/constitution.md` 定义的需求文档。本文档定义"做什么"，不定义"怎么做"。

## 1. 项目背景

这是一个用来实践 SPDD（Spec-Driven Development）方法论和端侧 ABR 算法的练手项目。目标是用"先定义 spec、再用 AI 按 spec 生成代码"的方式，在不熟悉的技术栈（iOS / Swift）上快速交付一个可运行的播放器，并验证自定义 BBA 算法和 QoS 监控的端侧落地。本 demo 的三个目标：① 实践 ABR 算法原理（BBA）② 用 SPDD 方法论驱动 AI 在新技术栈（iOS/Swift）上快速交付 ③ 落地 QoS 监控体系。

## 2. 用户故事

**作为** 播放器开发者，
**我想** 实现一个 iOS 播放器 demo，用自定义 BBA 算法覆盖 AVPlayer 默认 ABR，并实时显示 QoS 指标，
**以便** 验证端侧 ABR 策略和 QoS 监控的端侧落地，并实践用 SPDD 方法论在不熟悉的技术栈上快速交付。

**作为** 项目维护者，
**我想** 用 SPDD 流程（constitution→spec→plan→tasks→implement）开发这个 demo，
**以便** 让 constitution 约束 AI 生成的代码质量，实现"方法论定义标准、AI 加速实现、人把控质量和策略"的开发模式。

## 3. 功能需求

### FR-1：HLS 播放
- 播放 Apple BipBop 多码率 HLS 测试流
- 支持播放/暂停/进度拖动（scrubber + 时间标签）
- 支持 PiP（画中画，`AVPictureInPictureController`）与 AirPlay（`AVRoutePickerView`）
- 播放器视图占屏幕上半部分，16:9 比例

### FR-2：自定义 BBA / MPC 算法
- 解析 HLS master playlist 获取可用码率档位列表（按 peakBitRate 升序）
- 每 0.5s 执行一次 ABR 控制循环
- 支持 BBA 与 MPC 两种策略，运行时切换；策略参数由 `ABRConfig` 注入（来自 Settings）
- 通过 `preferredPeakBitRate` 转向 AVPlayer 选档
- 每次切档记录日志（时间、旧档、新档、buffer、原因）

### FR-3：QoS 实时面板（调试 sheet）
- 7 项 QoS 指标（见 constitution §4）在 Player 内以可切换的调试 sheet 呈现，不常驻主屏
- 每 0.5s 刷新一次
- 指标用 SwiftUI Text 实时更新，不需要图表

### FR-4：切档日志面板
- 在 QoS 调试 sheet 内显示最近 10 条切档记录
- 每条记录格式：`[时间] xxxkbps → xxxkbps (buffer: xx.xs, 原因)`

### FR-5：弱网模拟开关
- 在 Settings 与 Player 控制条均提供"模拟弱网"开关
- 弱网模式下人为限制 preferredPeakBitRate 到最低档（模拟带宽受限）
- 用于演示 ABR 在弱网下的降档行为

### FR-6：内容库（Library）
- 提供内置 HLS 测试流列表（Apple BipBop 4x3/16x9、Apple Advanced HLS、Mux x36xhzz、Tubi test stream）
- Library 以 `NavigationStack` + `List` 呈现，tap 进入 Player
- 持久化"最近播放"（SwiftData），app 重启后保留

### FR-7：设置页（Settings）
- ABR 策略选择（BBA / MPC）
- 参数 sliders：reservoir / cushion / hysteresis / w_stall / w_quality / w_switch
- 弱网开关、自动弱网（蜂窝网络下自动启用弱网模式）
- QoS 日志 CSV 导出按钮（ShareLink）
- 清空播放历史按钮
- 所有设置用 `@AppStorage` 持久化，app 重启后保留

### FR-8：持久化（SwiftData）
- `PlaybackHistoryItem`：流 URL、标题、上次播放位置、上次播放时间
- `QoSLogEntry`：每 0.5s 采样（timestamp, buffer, current_bitrate, observed_bitrate, target_bitrate, switch_count, stall_count）
- QoS 日志仅在调试模式开启时写入，自动截断到最近 N 条（避免无限增长）

### FR-9：音频会话与生命周期
- 配置 `AVAudioSession.Category.playback`
- 监听音频中断通知，中断时暂停、结束后恢复
- 监听路由变化（耳机插拔等）
- `scenePhase` 变化：后台时若 PiP 未激活则暂停，前台恢复

### FR-10：网络监控
- `NWPathMonitor` 检测 WiFi / cellular / none
- 网络类型显示在 QoS 调试 sheet
- 可选：蜂窝网络下自动启用弱网模式（Settings 开关）

### FR-11：错误处理 UI
- `AVPlayerItem.status == .failed` 或网络不可用时显示错误 overlay
- 提供重试按钮

### FR-12：日志
- 用 `os.Logger`（subsystem `com.abrplayer.demo`）替代 `print()`
- ABR 决策、切档、卡顿、错误均通过 `ABRLogger` 输出

## 4. 非功能需求

### NFR-1：性能
- 首帧耗时 ≤ 2s（WiFi 环境）
- ABR 控制循环周期 = 0.5s，不允许超过 1s
- QoS 面板刷新不卡顿主线程

### NFR-2：兼容性
- iOS 17+（需要 `@Observable` / `SwiftData` / `NavigationStack` 现代 API）
- 支持 iPhone 真机和模拟器
- 支持竖屏（不需要横屏适配）
- PiP 仅在真机可验证，模拟器构建不报错但功能不可用

### NFR-3：代码质量
- 所有 KVO 在 deinit 反注册
- 所有 Timer 在 deinit invalidate
- 无 force unwrap（除确认非 nil 的场景）
- 公开类型有文档注释
- ABR 算法在本地 Swift Package `ABREngine` 内，app target 仅依赖不内嵌实现

### NFR-4：测试
- `ABREngineTests`（XCTest）必须通过：BBA/MPC 在固定合成 trace 上的决策序列与 `scripts/simulate_abr.py` 输出逐拍一致
- 测试可独立于 app 运行（`xcodebuild test -scheme ABREngine`）

## 5. 验收标准

### AC-1：基础播放
- 从 Library 选流 → push 到 PlayerScreen 播放
- 首帧在 2s 内出现

### AC-2：ABR 切档可观察
- 正常网络下，启动后 buffer 逐渐升高，ABR 从最低档升到最高档
- QoS 调试 sheet 内切档日志能看到升档记录
- QoS 调试 sheet "当前档位"字段变化

### AC-3：弱网降档
- 开启"模拟弱网"后，buffer 下降
- buffer < reservoir 时 ABR 切到最低档
- 关闭弱网后，buffer 恢复，ABR 升档

### AC-4：QoS 指标实时更新
- 7 项指标在调试 sheet 内全部显示且每 0.5s 更新
- 数值非 0 非空（除首帧耗时在首帧后才有值）

### AC-5：客户端化
- Library 的最近播放与 Settings 参数在 app 重启后保留
- 后台时音频继续（PiP 激活）或暂停（未激活），中断来电后能恢复
- AirPlay 路由选择可用
- 播放失败时显示错误 overlay 且重试可恢复

### AC-6：算法对齐测试
- `xcodebuild test -scheme ABREngine` 通过：BBA/MPC 在固定 trace 上与 Python 仿真器逐拍一致

## 6. 范围外（明确不做）

- 不做音量控制
- 不做全屏播放（横屏全屏）
- 不做用户账号 / 云端同步
- 不做网络层抽象（直接用 AVPlayer 默认网络栈）
- 不做离线下载
