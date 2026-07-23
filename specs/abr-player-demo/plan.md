# Plan：iOS ABR Player Demo 技术方案

> 基于 `spec.md` 定义的技术实现方案。本文档定义"怎么做"。

## 1. 架构总览

```
┌─────────────────────────────────────────────────┐
│                  SwiftUI View                    │
│  ContentView                                      │
│   ├── PlayerView (AVPlayerLayer 包装)             │
│   ├── QoSDashboard (7 项指标)                     │
│   └── SwitchLogView (切档日志)                     │
└──────────────┬──────────────────────────────────┘
               │ @StateObject
┌──────────────▼──────────────────────────────────┐
│            ABRPlayerController (ObservableObject) │
│   ├── AVPlayer                                    │
│   ├── AVPlayerItem                                │
│   ├── BBAController (BBA 算法)                    │
│   ├── HLSVariantParser (档位解析)                 │
│   ├── QoSObservers (QoS 观察器)                   │
│   └── QoSMetrics (数据模型)                       │
└─────────────────────────────────────────────────┘
```

## 2. 模块设计

### 2.1 ABRPlayerController.swift
**职责**：封装 AVPlayer，作为 SwiftUI 的 ObservableObject，协调各子模块
**关键 API**：
- `init(url:)` —— 初始化播放器
- `play()` / `pause()`
- `seek(to:)`
- `@Published var metrics: QoSMetrics` —— 供 UI 订阅
- `@Published var switchLogs: [SwitchLog]` —— 供 UI 订阅

**生命周期**：
- init 时创建 AVPlayer、AVPlayerItem、BBAController、QoSObservers
- 启动 BBA 控制定时器（0.5s）
- deinit 时清理所有 Timer 和 KVO

### 2.2 HLSVariantParser.swift
**职责**：异步解析 HLS master playlist 获取码率档位列表
**关键 API**：
- `static func parse(from asset: AVURLAsset) async throws -> [HLSVariant]`
- `struct HLSVariant { let peakBitRate: Double; let url: URL }`
- 返回结果按 peakBitRate 升序排序

**实现要点**：
- 用 `await asset.load(.variants)` 异步加载（iOS 15+ API）
- 每个 variant 取 `peakBitRate` 和 `url`
- 失败时 throw `HLSVariantParserError`

### 2.3 BBAController.swift
**职责**：实现 BBA 算法，每 0.5s 决策一次目标码率
**关键 API**：
- `init(player: AVPlayer, variants: [HLSVariant])`
- `func start()` —— 启动 0.5s 定时器
- `func stop()` —— 停止定时器
- `var onSwitch: ((SwitchLog) -> Void)?` —— 切档回调
- `var currentTarget: Double?` —— 当前目标码率

**算法实现**（见 constitution §3）：
```swift
func decide(bufferSeconds: Double) -> Double {
    let sorted = variants.sorted { $0.peakBitRate < $1.peakBitRate }
    let minBR = sorted.first!.peakBitRate
    let maxBR = sorted.last!.peakBitRate
    
    let target: Double
    if bufferSeconds < reservoir {           // < 5s
        target = minBR
    } else if bufferSeconds > reservoir + cushion {  // > 15s
        target = maxBR
    } else {
        let ratio = (bufferSeconds - reservoir) / cushion
        let raw = minBR + ratio * (maxBR - minBR)
        target = quantize(raw, sorted, hysteresis: 0.8)
    }
    return target
}
```

**滞回量化**：
- 计算候选档位后，若新档位比当前档位高，需要 buffer 超过"目标档位阈值 * 1/0.8"才切换（向上难）
- 若新档位比当前档位低，buffer 低于"目标档位阈值 * 0.8"就切换（向下易）
- 这样实现"升档保守、降档激进"的滞回行为

### 2.4 QoSObservers.swift
**职责**：通过 KVO 和 NotificationCenter 观察 AVPlayer 状态，更新 QoSMetrics
**观察项**：
- `loadedTimeRanges` KVO → 计算 buffer 水位
- `timeControlStatus` KVO → 检测播放/暂停/等待（卡顿）
- `NSNotification.Name.AVPlayerItemNewAccessLogEntry` → 当前码率/观测吞吐
- 首帧计时：`play()` 调用时记录时间戳，`timeControlStatus == .playing` 时计算耗时

**关键 API**：
- `init(player: AVPlayer, playerItem: AVPlayerItem)`
- `func startObserving()`
- `func stopObserving()`
- `var onMetricsUpdate: ((QoSMetrics) -> Void)?`

### 2.5 QoSMetrics.swift
**职责**：QoS 数据模型
```swift
struct QoSMetrics {
    var currentBitrate: Double = 0       // kbps
    var observedBitrate: Double = 0      // kbps
    var bufferSeconds: Double = 0
    var firstFrameMs: Double = 0
    var switchCount: Int = 0
    var stallCount: Int = 0
    var currentVariant: HLSVariant?
}
```

### 2.6 SwitchLog.swift
```swift
struct SwitchLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let fromBitrate: Double
    let toBitrate: Double
    let bufferSeconds: Double
    let reason: String
}
```

### 2.7 Views
- `PlayerView.swift`：用 `AVVideoLayer` 通过 `UIViewRepresentable` 包装到 SwiftUI
- `QoSDashboard.swift`：用 `LazyVGrid` 显示 7 项指标
- `SwitchLogView.swift`：用 `List` 显示最近 10 条切档日志
- `ContentView.swift`：用 `VStack` 组合上述三个视图

## 3. 数据流

```
AVPlayer (播放)
   ↓ loadedTimeRanges (KVO)
QoSObservers → QoSMetrics.bufferSeconds
   ↓ 每 0.5s
BBAController.decide(bufferSeconds) → targetBitrate
   ↓
AVPlayerItem.preferredPeakBitRate = targetBitrate
   ↓
AVPlayer 响应新码率 → accessLog 更新
   ↓ NSNotification
QoSObservers → QoSMetrics.currentBitrate
   ↓ @Published
SwiftUI View 自动刷新
```

## 4. 关键技术决策

### 4.1 为什么用 `preferredPeakBitRate` 而不是替换 AVPlayerItem
- `preferredPeakBitRate` 是官方 API，设置后 AVPlayer 会优先选择不超过此值的最高档位
- 替换 AVPlayerItem 会触发重新加载、首帧延迟，不适合 0.5s 一次的控制循环
- 这是 iOS 上实现自定义 ABR 的标准方式

### 4.2 为什么用 KVO 而不是 Combine
- AVPlayer 的属性（loadedTimeRanges、timeControlStatus）原生支持 KVO
- Combine 包装 KVO 增加复杂度，demo 项目用原生 KVO 更直接
- iOS 17+ 有 Combine 友好的 API，但为了兼容 iOS 16 用 KVO

### 4.3 为什么 BBA 而不是 MPC / Rate-Based
- BBA 只依赖 buffer，不依赖带宽预测，实现简单且鲁棒
- MPC 需要准确的带宽预测和吞吐模型，demo 项目不必要
- Rate-Based 在带宽抖动时切档频繁，BBA 的 buffer 缓冲更稳定
- BBA 是 SIGCOM 经典论文，原理清晰、易于讲解

## 5. 风险与应对

| 风险 | 应对 |
|---|---|
| BipBop 流只有 2 个档位，BBA 效果不明显 | 备选 Tubi 测试流或 Apple Advanced HLS stream |
| AVPlayer 不响应 preferredPeakBitRate | 已确认是官方 API，论坛有成功案例 |
| KVO 反注册遗漏导致崩溃 | 在 deinit 严格清理，用 NSKeyValueObservation token |
| 模拟器 Network Link Conditioner 不稳定 | 用"模拟弱网"按钮直接限制 preferredPeakBitRate |

## 6. 实现顺序

按 tasks.md 执行，分 3 天：
- Day 1 PM：基础播放（FR-1）
- Day 2：BBA + QoS（FR-2、FR-3、FR-4）
- Day 3：弱网测试 + README（FR-5、AC-3、AC-4）
