# Tasks：iOS ABR Player Demo 任务拆解

> 给 AI 执行的清单。每个 task 是一个可独立验证的工作单元。

## Day 1 PM：Xcode 项目搭建 + 基础播放

### T1.1 Xcode 项目初始化
- [ ] Xcode 新建 App 项目，命名 `ABRPlayerDemo`
- [ ] Interface 选 SwiftUI
- [ ] Language 选 Swift
- [ ] Minimum Deployments 设 iOS 16.0
- [ ] 保存到 `abr-player-demo/ABRPlayerDemo/`
- **验证**：项目能在模拟器编译运行，显示默认 ContentView

### T1.2 ABRPlayerController 基础封装
- [ ] 创建 `ABR/ABRPlayerController.swift`
- [ ] 封装 AVPlayer + AVPlayerItem
- [ ] 提供 `init(url: URL)` 初始化
- [ ] 提供 `play()` / `pause()` 方法
- [ ] 作为 `ObservableObject`，`@Published var isPlaying: Bool`
- **验证**：能在 controller 调用 play 后 AVPlayer 开始播放

### T1.3 PlayerView SwiftUI 包装
- [ ] 创建 `Views/PlayerView.swift`
- [ ] 用 `UIViewRepresentable` 包装 `AVPlayerLayer`
- [ ] 接收 `AVPlayer` 作为参数
- [ ] 设置 videoGravity 为 `.resizeAspect`
- **验证**：SwiftUI 中能显示 AVPlayer 画面

### T1.4 ContentView 基础布局
- [ ] 创建 `ContentView.swift`（覆盖默认）
- [ ] `@StateObject var controller: ABRPlayerController`
- [ ] `VStack` 布局：PlayerView 占上半部分，下半部分留空
- [ ] `.task { controller.play() }` 自动播放
- [ ] 用 BipBop URL：`https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8`
- **验证**：模拟器能播放 BipBop 流，首帧 ≤ 2s

## Day 2 AM：HLS 档位解析 + BBA 算法

### T2.1 HLSVariantParser 实现
- [ ] 创建 `ABR/HLSVariantParser.swift`
- [ ] 定义 `struct HLSVariant: Equatable { let peakBitRate: Double; let url: URL }`
- [ ] 实现 `static func parse(from asset: AVURLAsset) async throws -> [HLSVariant]`
- [ ] 用 `await asset.load(.variants)` 异步加载
- [ ] 提取每个 variant 的 `peakBitRate` 和 `url`
- [ ] 按 `peakBitRate` 升序排序返回
- [ ] 失败 throw `HLSVariantParserError`
- **验证**：能从 BipBop 流解析出档位列表（至少 2 个）

### T2.2 BBAController 算法核心
- [ ] 创建 `ABR/BBAController.swift`
- [ ] 定义常量 `reservoir = 5.0`、`cushion = 10.0`、`hysteresis = 0.8`
- [ ] 实现 `func decide(bufferSeconds: Double) -> Double`（按 plan §2.3）
- [ ] 实现 `quantize(_:variants:hysteresis:)` 滞回量化
- [ ] 实现 `func start()`：用 `Timer.scheduledTimer` 每 0.5s 调用 `controlLoop()`
- [ ] `controlLoop()` 内：
  - 从 playerItem.loadedTimeRanges 计算 bufferSeconds
  - 调用 `decide()` 得到 targetBitrate
  - 若 target != currentTarget，记录 SwitchLog，设置 `playerItem.preferredPeakBitRate`
- [ ] 实现 `func stop()`：invalidate timer
- [ ] 定义 `var onSwitch: ((SwitchLog) -> Void)?` 回调
- **验证**：BBA 能根据 buffer 自动调整 preferredPeakBitRate

### T2.3 SwitchLog 模型
- [ ] 创建 `Models/SwitchLog.swift`
- [ ] 定义 `struct SwitchLog: Identifiable { let id = UUID(); let timestamp: Date; let fromBitrate: Double; let toBitrate: Double; let bufferSeconds: Double; let reason: String }`
- **验证**：编译通过

## Day 2 PM：QoS 观察器 + 面板

### T2.4 QoSMetrics 模型
- [ ] 创建 `Models/QoSMetrics.swift`
- [ ] 定义 `struct QoSMetrics` 含 7 项字段（见 plan §2.5）
- [ ] 所有字段有默认值
- **验证**：编译通过

### T2.5 QoSObservers 实现
- [ ] 创建 `ABR/QoSObservers.swift`
- [ ] 用 `NSKeyValueObservation` 观察 `playerItem.loadedTimeRanges` → 计算 bufferSeconds
- [ ] 用 `NSKeyValueObservation` 观察 `player.timeControlStatus` → 检测卡顿（waitingToPlay + toMinimizeStalls）
- [ ] 用 `NotificationCenter` 监听 `AVPlayerItemNewAccessLogEntry` → 取 `indicatedBitrate` / `observedBitrate`
- [ ] 首帧计时：在 `play()` 调用时记录 startTimestamp，`timeControlStatus == .playing` 时计算耗时
- [ ] 定义 `var onMetricsUpdate: ((QoSMetrics) -> Void)?` 回调
- [ ] 实现 `func startObserving()` / `func stopObserving()`
- [ ] 在 deinit 调用 stopObserving
- **验证**：能从观察器获取 7 项指标

### T2.6 ABRPlayerController 整合
- [ ] 在 ABRPlayerController.init 中创建 HLSVariantParser、BBAController、QoSObservers
- [ ] `@Published var metrics: QoSMetrics`
- [ ] `@Published var switchLogs: [SwitchLog]`
- [ ] 启动 BBA timer 和 QoS observers
- [ ] onMetricsUpdate 回调更新 metrics
- [ ] onSwitch 回调追加 switchLogs（保留最近 10 条）
- **验证**：controller 能协调所有模块

### T2.7 QoSDashboard 视图
- [ ] 创建 `Views/QoSDashboard.swift`
- [ ] 接收 `QoSMetrics` 作为参数
- [ ] 用 `LazyVGrid(columns: 2)` 显示 7 项指标
- [ ] 每项指标用 `VStack { Text(title).font(.caption); Text(value).font(.title3.bold()) }`
- [ ] 数字格式化：码率用 kbps，buffer 用 1 位小数，首帧用 ms
- **验证**：UI 能显示 7 项指标

### T2.8 SwitchLogView 视图
- [ ] 创建 `Views/SwitchLogView.swift`
- [ ] 接收 `[SwitchLog]` 作为参数
- [ ] 用 `List` 显示最近 10 条
- [ ] 每条格式：`[HH:mm:ss] xxxkbps → xxxkbps (buf: xx.xs, 原因)`
- **验证**：UI 能显示切档日志

### T2.9 ContentView 整合
- [ ] 修改 ContentView：VStack { PlayerView; QoSDashboard; SwitchLogView }
- [ ] 用 `.onReceive` 订阅 controller 的 metrics 和 switchLogs
- **验证**：完整 demo 跑通，BBA 切档可观察

## Day 3 AM：弱网测试 + 调试

### T3.1 模拟弱网按钮
- [ ] 在 ContentView 加一个 Toggle "模拟弱网"
- [ ] 弱网模式下，BBAController 强制 target = variants.min（绕过 BBA 决策）
- [ ] 关闭后恢复 BBA 决策
- **验证**：开启弱网后 buffer 下降，BBA 降档；关闭后恢复

### T3.2 调试滞回参数
- [ ] 测试 hysteresis = 0.8 在 BipBop 流上的切档频率
- [ ] 若切档过于频繁，调到 0.7；若过于保守，调到 0.9
- [ ] 记录最终参数到 README
- **验证**：切档频率合理（不应每秒都切）

### T3.3 修复常见问题
- [ ] 检查所有 KVO 在 deinit 反注册
- [ ] 检查所有 Timer 在 deinit invalidate
- [ ] 检查 AVPlayerItem 替换时清理观察者
- [ ] 检查 force unwrap
- **验证**：长时间运行无崩溃

## Day 3 PM：README + 项目讲解话术

### T3.4 README 编写
- [ ] 创建 `README.md`
- [ ] 包含：项目背景、SPDD 流程说明（链接 4 份文档）、BBA 算法说明、QoS 指标说明、如何用 AI 实现的诚实说明、运行步骤
- **验证**：README 完整

### T3.5 项目讲解话术准备
- [ ] 在 README 末尾写 3 分钟 demo 讲解话术
- [ ] 包含：SPDD 流程、BBA 算法、QoS 面板、诚实声明
- **验证**：话术流畅，3 分钟内讲完

### T3.6 录 demo 视频
- [ ] 录屏：正常网络下 BBA 升档 + 弱网下 BBA 降档 + QoS 面板实时变化
- [ ] 时长 3 分钟以内
- **验证**：视频能展示 BBA 行为
