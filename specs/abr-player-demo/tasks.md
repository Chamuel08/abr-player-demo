# Tasks：iOS ABR Player Demo 任务拆解

> 给 AI 执行的清单。每个 task 是一个可独立验证的工作单元。

## Day 1 PM：Xcode 项目搭建 + 基础播放

### T1.1 Xcode 项目初始化
- [x] Xcode 新建 App 项目，命名 `ABRPlayerDemo`
- [x] Interface 选 SwiftUI
- [x] Language 选 Swift
- [x] Minimum Deployments 设 iOS 16.0
- [x] 保存到 `abr-player-demo/ABRPlayerDemo/`
- **验证**：项目能在模拟器编译运行，显示默认 ContentView

### T1.2 ABRPlayerController 基础封装
- [x] 创建 `ABR/ABRPlayerController.swift`
- [x] 封装 AVPlayer + AVPlayerItem
- [x] 提供 `init(url: URL)` 初始化
- [x] 提供 `play()` / `pause()` 方法
- [x] 作为 `ObservableObject`，`@Published var isPlaying: Bool`
- **验证**：能在 controller 调用 play 后 AVPlayer 开始播放

### T1.3 PlayerView SwiftUI 包装
- [x] 创建 `Views/PlayerView.swift`
- [x] 用 `UIViewRepresentable` 包装 `AVPlayerLayer`
- [x] 接收 `AVPlayer` 作为参数
- [x] 设置 videoGravity 为 `.resizeAspect`
- **验证**：SwiftUI 中能显示 AVPlayer 画面

### T1.4 ContentView 基础布局
- [x] 创建 `ContentView.swift`（覆盖默认）
- [x] `@StateObject var controller: ABRPlayerController`
- [x] `VStack` 布局：PlayerView 占上半部分，下半部分留空
- [x] `.task { controller.play() }` 自动播放
- [x] 用 BipBop URL：`https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8`
- **验证**：模拟器能播放 BipBop 流，首帧 ≤ 2s

## Day 2 AM：HLS 档位解析 + BBA 算法

### T2.1 HLSVariantParser 实现
- [x] 创建 `ABR/HLSVariantParser.swift`
- [x] 定义 `struct HLSVariant: Equatable { let peakBitRate: Double; let url: URL }`
- [x] 实现 `static func parse(from asset: AVURLAsset) async throws -> [HLSVariant]`
- [x] 用 `await asset.load(.variants)` 异步加载
- [x] 提取每个 variant 的 `peakBitRate` 和 `url`
- [x] 按 `peakBitRate` 升序排序返回
- [x] 失败 throw `HLSVariantParserError`
- **验证**：能从 BipBop 流解析出档位列表（至少 2 个）

### T2.2 BBAController 算法核心
- [x] 创建 `ABR/BBAController.swift`
- [x] 定义常量 `reservoir = 5.0`、`cushion = 10.0`、`hysteresis = 0.8`
- [x] 实现 `func decide(bufferSeconds: Double) -> Double`（按 plan §2.3）
- [x] 实现 `quantize(_:variants:hysteresis:)` 滞回量化
- [x] 实现 `func start()`：用 `Timer.scheduledTimer` 每 0.5s 调用 `controlLoop()`
- [x] `controlLoop()` 内：
  - 从 playerItem.loadedTimeRanges 计算 bufferSeconds
  - 调用 `decide()` 得到 targetBitrate
  - 若 target != currentTarget，记录 SwitchLog，设置 `playerItem.preferredPeakBitRate`
- [x] 实现 `func stop()`：invalidate timer
- [x] 定义 `var onSwitch: ((SwitchLog) -> Void)?` 回调
- **验证**：BBA 能根据 buffer 自动调整 preferredPeakBitRate

### T2.3 SwitchLog 模型
- [x] 创建 `Models/SwitchLog.swift`
- [x] 定义 `struct SwitchLog: Identifiable { let id = UUID(); let timestamp: Date; let fromBitrate: Double; let toBitrate: Double; let bufferSeconds: Double; let reason: String }`
- **验证**：编译通过

## Day 2 PM：QoS 观察器 + 面板

### T2.4 QoSMetrics 模型
- [x] 创建 `Models/QoSMetrics.swift`
- [x] 定义 `struct QoSMetrics` 含 7 项字段（见 plan §2.5）
- [x] 所有字段有默认值
- **验证**：编译通过

### T2.5 QoSObservers 实现
- [x] 创建 `ABR/QoSObservers.swift`
- [x] 用 `NSKeyValueObservation` 观察 `playerItem.loadedTimeRanges` → 计算 bufferSeconds
- [x] 用 `NSKeyValueObservation` 观察 `player.timeControlStatus` → 检测卡顿（waitingToPlay + toMinimizeStalls）
- [x] 用 `NotificationCenter` 监听 `AVPlayerItemNewAccessLogEntry` → 取 `indicatedBitrate` / `observedBitrate`
- [x] 首帧计时：在 `play()` 调用时记录 startTimestamp，`timeControlStatus == .playing` 时计算耗时
- [x] 定义 `var onMetricsUpdate: ((QoSMetrics) -> Void)?` 回调
- [x] 实现 `func startObserving()` / `func stopObserving()`
- [x] 在 deinit 调用 stopObserving
- **验证**：能从观察器获取 7 项指标

### T2.6 ABRPlayerController 整合
- [x] 在 ABRPlayerController.init 中创建 HLSVariantParser、BBAController、QoSObservers
- [x] `@Published var metrics: QoSMetrics`
- [x] `@Published var switchLogs: [SwitchLog]`
- [x] 启动 BBA timer 和 QoS observers
- [x] onMetricsUpdate 回调更新 metrics
- [x] onSwitch 回调追加 switchLogs（保留最近 10 条）
- **验证**：controller 能协调所有模块

### T2.7 QoSDashboard 视图
- [x] 创建 `Views/QoSDashboard.swift`
- [x] 接收 `QoSMetrics` 作为参数
- [x] 用 `LazyVGrid(columns: 2)` 显示 7 项指标
- [x] 每项指标用 `VStack { Text(title).font(.caption); Text(value).font(.title3.bold()) }`
- [x] 数字格式化：码率用 kbps，buffer 用 1 位小数，首帧用 ms
- **验证**：UI 能显示 7 项指标

### T2.8 SwitchLogView 视图
- [x] 创建 `Views/SwitchLogView.swift`
- [x] 接收 `[SwitchLog]` 作为参数
- [x] 用 `List` 显示最近 10 条
- [x] 每条格式：`[HH:mm:ss] xxxkbps → xxxkbps (buf: xx.xs, 原因)`
- **验证**：UI 能显示切档日志

### T2.9 ContentView 整合
- [x] 修改 ContentView：VStack { PlayerView; QoSDashboard; SwitchLogView }
- [x] 用 `.onReceive` 订阅 controller 的 metrics 和 switchLogs
- **验证**：完整 demo 跑通，BBA 切档可观察

## Day 3 AM：弱网测试 + 调试

### T3.1 模拟弱网按钮
- [x] 在 ContentView 加一个 Toggle "模拟弱网"
- [x] 弱网模式下，BBAController 强制 target = variants.min（绕过 BBA 决策）
- [x] 关闭后恢复 BBA 决策
- **验证**：开启弱网后 buffer 下降，BBA 降档；关闭后恢复

### T3.2 调试滞回参数
- [x] 测试 hysteresis = 0.8 在 BipBop 流上的切档频率
- [x] 若切档过于频繁，调到 0.7；若过于保守，调到 0.9
- [x] 记录最终参数到 README
- **验证**：切档频率合理（不应每秒都切）

### T3.3 修复常见问题
- [x] 检查所有 KVO 在 deinit 反注册
- [x] 检查所有 Timer 在 deinit invalidate
- [x] 检查 AVPlayerItem 替换时清理观察者
- [x] 检查 force unwrap
- **验证**：长时间运行无崩溃

## Day 3 PM：README + 项目讲解要点

### T3.4 README 编写
- [x] 创建 `README.md`
- [x] 包含：项目背景、SPDD 流程说明（链接 4 份文档）、BBA 算法说明、QoS 指标说明、开发方式说明、运行步骤
- **验证**：README 完整

### T3.5 项目讲解要点准备
- [x] 在 README 末尾写 3 分钟 demo 讲解要点
- [x] 包含：SPDD 流程、BBA 算法、QoS 面板、开发方式说明
- **验证**：讲解流畅，3 分钟内讲完

### T3.6 录 demo 视频
- [ ] 录屏：正常网络下 BBA 升档 + 弱网下 BBA 降档 + QoS 面板实时变化
- [ ] 时长 3 分钟以内
- **验证**：视频能展示 BBA 行为

## 阶段三：离线参数校准（对应 spec-calibration.md）

### T4.1 公开 trace 数据集接入
- [x] 创建 `scripts/download_traces.sh`，拉取 confiwent/Real-world-bandwidth-traces（MIT）
- [x] `.gitignore` 排除 `data/`，数据集不入库
- [x] 校验各子集 trace 数量
- **验证**：脚本可重复执行（已存在则 skip）

### T4.2 ABR 离线仿真器
- [x] 创建 `scripts/simulate_abr.py`，纯标准库
- [x] `BBAPolicy` 与 BBAController.decide/quantize 逐行对齐
- [x] `MPCPolicy` 与 MPCController.decide/rolloutCost 逐行对齐（含三种安全兜底）
- [x] buffer 动力学按"下载进度 + 播放消耗"真实推演，不复用 MPC 预测模型
- [x] 区分首帧耗时与卡顿（起播前的 buffer 填充不计卡顿）
- [x] 吞吐为 0 的采样点防零
- **验证**：同一 trace 重复运行结果完全一致；弱网开关下强制最低档、0 切档

### T4.3 参数网格搜索
- [x] 创建 `scripts/grid_search.py`，支持 `--jobs` 多进程
- [x] 训练集搜参、测试集报数
- [x] 输出 Pareto 前沿（按 (码率, 卡顿) 去重）
- [x] 测试集复核：搜索最优 vs 当前 Swift 默认参数
- **验证**：BBA 全网格 125 组 <1s；MPC 729 组约 4s

### T4.4 真机验收（待办）
- [ ] 把候选参数在真机上过 Network Link Conditioner（3G profile）
- [ ] 对比真机 QoS 与仿真预测的偏差
- [ ] 通过验收后才写回 `BBAController.swift` / `MPCController.swift`
- **验证**：仿真结论在真实 AVPlayer 上成立

### T4.5 MPC 时域粒度修正
- [x] 定位根因：初版 `horizon×dt = 5s ≈ reservoir`，rollout 里 buffer 推不到 0、卡顿项恒为 0
- [x] 对照 FastMPC/RobustMPC 标准形式，改为按 segment 决策（`dt = 4s`，`H = 5`，窗口 20s）
- [x] 卡顿惩罚改为按秒计（线性插值折算见底秒数），画质项乘 `dt`，量纲与 `dt` 解耦
- [x] rollout 与安全兜底节奏解耦：rollout 每 segment 重算，兜底仍每 0.5s 检查
- [x] `horizon` / `mpc_dt` 提为仿真器可搜参数，扫描确认窗口 ≤8s 时卡顿项失效
- [x] 同步 spec-mpc.md（含两条 CRITICAL）与 roadmap 阶段二验收说明
- **验证**：测试集 MPC 卡顿 10.26s ≤ BBA 10.33s，切档 15.0 vs 41.8，QoE -0.791 > -0.826 ✓

### T4.6 MPC 代价权重写回（待办）
- [ ] 搜参最优 `w_stall=50 w_quality=20 w_switch=100 reservoir=8 cushion=6`，测试集 2299 kbps / 9.89s / QoE 0.562
- [ ] 收益看着过好（码率 4.6 倍而卡顿仅降 0.4s），需真机确认是否为仿真未建模的响应延迟所致
- [ ] 通过 T4.4 验收后才写回 `MPCController.swift`
- **验证**：真机 QoS 与仿真预测偏差在可解释范围内

## 阶段四：客户端化重构（对应 constitution v2.0）

> 把"单屏算法 demo"重构成真实 iOS 客户端项目。iOS 17+ / `@Observable` / `SwiftData` / `NavigationStack`；ABREngine 抽成本地 Swift Package；QoS 改调试 sheet；新增音频会话/PiP/AirPlay/生命周期/网络监控/错误 UI/CSV 导出/XCTest。

### T5.1 文档先行
- [x] constitution v2.0：iOS 16+ → 17+（MAJOR），§4 注明 QoS 改调试 sheet，§5 加 XCTest 守对齐，§6 加 ABRConfig 注入
- [x] spec.md：加 FR-6~FR-12（Library/Settings/持久化/音频会话/网络监控/错误 UI/日志）、NFR-4（测试）、AC-5/AC-6
- [x] plan.md：架构图换三层 mermaid，模块设计改 Features/Infrastructure/Package
- [x] tasks.md：加阶段四任务
- [x] roadmap.md：标注阶段四
- **验证**：四份文档自洽，无与 constitution 冲突处

### T5.2 ABREngine Swift Package
- [ ] 建 `Packages/ABREngine/Package.swift`（iOS 17+，library `ABREngine`，test target `ABREngineTests`）
- [ ] 移入 `Sources/ABREngine/Models/`：`HLSVariant.swift`、`QoSMetrics.swift`、`SwitchLog.swift`
- [ ] 新增 `Sources/ABREngine/Models/ABRConfig.swift`：参数 struct
- [ ] 移入 `Sources/ABREngine/Policies/`：`ABRController.swift`、`BBAController.swift`、`MPCController.swift`、`ThroughputEstimator.swift`，改造为接收 `ABRConfig`
- [ ] 移入 `Sources/ABREngine/Parser/HLSVariantParser.swift`
- [ ] 新增 `Sources/ABREngine/Logging/ABRLogger.swift`：`os.Logger` 封装
- [ ] 所有公开类型加 `public` 修饰符 + 文档注释
- **验证**：`swift build` 包独立编译通过

### T5.3 ABREngineTests 对齐测试
- [ ] 在 `Tests/ABREngineTests/` 写 `BBAPolicyParityTests.swift`：用固定合成 trace 喂 `BBAController.decide`，断言决策序列与 `simulate_abr.py` 的 `BBAPolicy` 输出逐拍一致
- [ ] 写 `MPCPolicyParityTests.swift`：同上对 MPC
- [ ] 写 `ThroughputEstimatorTests.swift`：EWMA 收敛行为
- [ ] 期望值从 Python 仿真器跑出来填入测试
- **验证**：`swift test` 通过

### T5.4 gen_pbxproj.py 扩展
- [ ] `sources` 列表换成新 app 文件清单（删旧 ABR/Models/Views，加新 App/Features/Infrastructure）
- [ ] 新增 `XCLocalSwiftPackageReference`（path `../Packages/ABREngine`）和 `XCSwiftPackageProductDependency`（product `ABREngine`）段
- [ ] `PBXProject.packageReferences` 加本地包引用
- [ ] `PBXNativeTarget.packageProductDependencies` 加 `ABREngine`
- [ ] 重新生成 `project.pbxproj`
- **验证**：Xcode 打开工程，app target 能链接 `ABREngine`，能 build

### T5.5 AppEnvironment + SettingsStore + StreamLibrary
- [ ] `App/AppEnvironment.swift`：`@Observable` 依赖容器
- [ ] `App/SettingsStore.swift`：`@AppStorage` 包装所有标量
- [ ] `App/StreamLibrary.swift`：内置流列表（BipBop 4x3/16x9、Apple Advanced HLS、Mux x36xhzz、Tubi）+ recents
- **验证**：app 启动不崩，Environment 可注入

### T5.6 Library + NavigationStack/TabView
- [ ] `Features/Library/LibraryView.swift` + `LibraryViewModel.swift` + `StreamRow.swift`
- [ ] `NavigationStack` + `List`，tap 推到 PlayerScreen
- [ ] TabView：Library / Settings
- **验证**：库列表显示，tap 能跳转

### T5.7 PlayerScreen + PlayerViewModel
- [ ] `Features/Player/PlayerScreen.swift`：替代旧 ContentView
- [ ] `Features/Player/PlayerViewModel.swift`：`@Observable`，拆旧 `ABRPlayerController`，播放 + ABR + QoS 采样写 SwiftData
- [ ] 接入 `ABREngine` 的 `ABRController`，参数从 `SettingsStore` 注入
- **验证**：能播放，ABR 接管，切档可观察

### T5.8 PlayerControlsBar + PlayerView(PiP 兼容)
- [ ] `Features/Player/PlayerControlsBar.swift`：play/pause、scrubber + 时间标签、PiP 按钮、AirPlay、策略 picker
- [ ] `Features/Player/PlayerView.swift`：保留 `UIViewRepresentable`，暴露 `AVPlayerLayer` 引用
- **验证**：控制条可用，scrubber 能拖

### T5.9 QoSDebugSheet
- [ ] `Features/Player/QoSDebugSheet.swift`：移自 `Views/QoSDashboard.swift`，作为 sheet 呈现
- [ ] `Features/Logs/SwitchLogView.swift`：移自 `Views/`，sheet 内组件
- [ ] PlayerScreen 加调试 sheet 入口按钮
- **验证**：sheet 能弹出，7 项指标 + 切档日志显示

### T5.10 SettingsView
- [ ] `Features/Settings/SettingsView.swift` + `SettingsViewModel.swift`
- [ ] 参数 sliders（reservoir/cushion/hysteresis/w_stall/w_quality/w_switch）
- [ ] 策略选择、弱网开关、自动弱网开关、CSV 导出按钮、清空历史
- **验证**：改参数后 ABR 行为实时变化

### T5.11 SwiftData 持久化
- [ ] `PlaybackHistoryItem` 模型
- [ ] `QoSLogEntry` 模型
- [ ] PlayerViewModel 每 0.5s 写 QoSLogEntry（仅调试模式）
- [ ] 自动截断到最近 N 条
- **验证**：app 重启后历史与采样保留

### T5.12 AudioSessionManager + LifecycleHandler
- [ ] `Infrastructure/AudioSessionManager.swift`：`.playback`，中断/路由通知
- [ ] `Infrastructure/LifecycleHandler.swift`：scenePhase 后台暂停（PiP 除外）
- **验证**：中断来电后能恢复，后台行为正确

### T5.13 PiPCoordinator + Info.plist
- [ ] `Infrastructure/PiPCoordinator.swift`：`AVPictureInPictureController`
- [ ] `Resources/Info.plist`：`UIBackgroundModes = [audio]`
- **验证**：真机 PiP 可用（模拟器不可验证）

### T5.14 NetworkMonitor
- [ ] `Infrastructure/NetworkMonitor.swift`：`NWPathMonitor`
- [ ] 接入 Settings 自动弱网 + QoS 面板显示网络类型
- **验证**：WiFi/cellular 切换可观察

### T5.15 QoSLogExporter
- [ ] `Infrastructure/QoSLogExporter.swift`：SwiftData → CSV → ShareLink
- **验证**：能导出 CSV 并分享

### T5.16 错误 UI
- [ ] PlayerScreen 加错误 overlay（`AVPlayerItem.status == .failed` 或网络不可用）
- [ ] 重试按钮
- **验证**：断网时显示 overlay，重试可恢复

### T5.17 README/文档更新
- [ ] README：新项目结构、新运行步骤、架构说明
- [ ] 标注阶段四完成
- **验证**：README 与代码一致
