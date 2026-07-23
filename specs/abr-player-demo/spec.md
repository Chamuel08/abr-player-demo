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
- 支持播放/暂停/进度拖动
- 播放器视图占屏幕上半部分，16:9 比例

### FR-2：自定义 BBA 算法
- 解析 HLS master playlist 获取可用码率档位列表（按 peakBitRate 升序）
- 每 0.5s 执行一次 BBA 控制循环
- 根据 buffer 水位按 BBA 公式计算目标码率
- 通过 `preferredPeakBitRate` 转向 AVPlayer 选档
- 每次切档记录日志（时间、旧档、新档、buffer、原因）

### FR-3：QoS 实时面板
- 屏幕下半部分显示 7 项 QoS 指标（见 constitution §4）
- 每 0.5s 刷新一次
- 指标用 SwiftUI Text 实时更新，不需要图表

### FR-4：切档日志面板
- 显示最近 10 条切档记录
- 每条记录格式：`[时间] xxxkbps → xxxkbps (buffer: xx.xs, 原因)`

### FR-5：弱网模拟开关
- 提供一个按钮切换"模拟弱网"模式
- 弱网模式下人为限制 preferredPeakBitRate 到最低档（模拟带宽受限）
- 用于演示 BBA 在弱网下的降档行为

## 4. 非功能需求

### NFR-1：性能
- 首帧耗时 ≤ 2s（WiFi 环境）
- BBA 控制循环周期 = 0.5s，不允许超过 1s
- QoS 面板刷新不卡顿主线程

### NFR-2：兼容性
- iOS 16+（需要 `AVURLAsset.load(.variants)` 异步 API）
- 支持 iPhone 真机和模拟器
- 支持竖屏（不需要横屏适配）

### NFR-3：代码质量
- 所有 KVO 在 deinit 反注册
- 所有 Timer 在 deinit invalidate
- 无 force unwrap（除确认非 nil 的场景）
- 公开类型有文档注释

## 5. 验收标准

### AC-1：基础播放
- 打开 app 自动播放 BipBop 流
- 首帧在 2s 内出现

### AC-2：BBA 切档可观察
- 正常网络下，启动后 buffer 逐渐升高，BBA 从最低档升到最高档
- 切档日志面板能看到升档记录
- QoS 面板"当前档位"字段变化

### AC-3：弱网降档
- 开启"模拟弱网"后，buffer 下降
- buffer < 5s 时 BBA 切到最低档
- 关闭弱网后，buffer 恢复，BBA 升档

### AC-4：QoS 指标实时更新
- 7 项指标全部显示且每 0.5s 更新
- 数值非 0 非空（除首帧耗时在首帧后才有值）

## 6. 范围外（明确不做）

- 不做音量控制
- 不做全屏播放
- 不做多视频列表
- 不做设置页
- 不做持久化存储
- 不做网络层抽象（直接用 AVPlayer 默认网络栈）
- 不做单元测试（demo 项目，手动验收）
