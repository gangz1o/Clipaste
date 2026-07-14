# 屏幕贴图实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变现有卡片对外拖拽的前提下，为图片历史记录增加可选的屏幕贴图能力。

**Architecture:** 新增 `@Observable ScreenPinViewModel` 管理开关和创建流程，复用 `ClipboardImagePipeline` 的后台下采样与有界缓存，`ScreenPinWindowCoordinator` 负责 AppKit 窗口生命周期。来源应用图标上的 `ScreenPinIconDragTarget` 使用内部拖拽会话回传松开坐标，与现有 `universalDragProvider` 完全分离。

**Tech Stack:** Swift 5、SwiftUI、Observation、AppKit、UniformTypeIdentifiers、String Catalog，无新增第三方依赖。

---

### Task 1: 用 TDD 定义贴图几何规则

**Files:**
- Create: `scripts/ScreenPinGeometryTests.swift`
- Create: `scripts/ScreenPinViewModelTestSupport.swift`
- Create: `scripts/ScreenPinViewModelTests.swift`
- Create: `scripts/ScreenPinEligibilityTestSupport.swift`
- Create: `scripts/ScreenPinEligibilityTests.swift`
- Create: `scripts/ScreenPinDragHitTest.swift`
- Create: `scripts/ScreenPinDragRuntimeHarness.swift`
- Create: `clipaste/Models/ScreenPinGeometry.swift`

- [x] 先创建失败测试，覆盖过大图等比缩小到 60%、过小图放大到最长边 240 pt、帧位置夹紧到 `visibleFrame` 和最小/最大尺寸保持宽高比。
- [x] 运行 `swiftc -parse-as-library -framework AppKit scripts/ScreenPinGeometryTests.swift -o /tmp/screen-pin-geometry-tests`，确认因 `ScreenPinGeometry` 尚不存在而失败。
- [x] 实现纯几何 API：`initialSize(imageSize:visibleFrame:)`、`minimumSize(imageSize:maximumSize:)`、`maximumSize(imageSize:visibleFrame:)` 和 `clampedFrame(size:centeredAt:visibleFrame:)`。
- [x] 运行 `swiftc -parse-as-library -framework AppKit clipaste/Models/ScreenPinGeometry.swift clipaste/Models/ScreenPinRenderPolicy.swift scripts/ScreenPinGeometryTests.swift -o /tmp/screen-pin-geometry-tests && /tmp/screen-pin-geometry-tests`，确认全部断言通过。
- [x] 使用协议注入夹具验证 ViewModel 默认关闭、偏好持久化、类型过滤、成功创建和关闭开关的取消竞态。
- [x] 使用生产 `ClipboardItem` 和 `ClipboardFileReference` 验证图片、图片文件、非图片文件及其余内容类型的贴图资格判断。
- [x] 增加 window-backed 命中测试与真实鼠标事件 harness，覆盖父级 `.onDrag` 和专用 AppKit 拖拽源的手势隔离。

### Task 2: 实现贴图 ViewModel 与高性能图片加载

**Files:**
- Create: `clipaste/ViewModels/ScreenPinViewModel.swift`
- Modify: `clipaste/Models/ClipboardItem.swift`
- Modify: `clipaste/Managers/ClipboardImagePipeline.swift`

- [x] 为 `ClipboardItem` 新增仅读 `isScreenPinEligible`，仅对 `.image` 和 `fileURL && fileRepresentsImage` 返回 `true`。
- [x] 扩展 `ClipboardImagePipeline` 新增贴图图片和贴图文件图片方法，沿用已有后台队列、ImageIO 下采样、`NSCache` 256 项/64 MB 上限和含目标像素尺寸的缓存键。
- [x] 按屏幕 backing scale 计算目标像素尺寸，最长边上限 4096 px，不在主演员上读文件或解码。
- [x] 文件采用后台分块读取和协作取消；同键任务使用请求代次隔离，旧请求不能移除或污染重新启用后的新请求。
- [x] 缓存成本按解码后像素尺寸计算，避免使用 JPEG 等压缩源字节数低估内存。
- [x] 实现 `@MainActor @Observable ScreenPinViewModel`：用 `UserDefaults` 读写默认为 `false` 的 `isEnabled`，异步调用图片管线，失败时设置 `operationNotice`，关闭开关时取消 pending tasks 并关闭全部贴图。
- [x] 每个加载任务在解码后检查 `Task.isCancelled` 和 `isEnabled`，禁止关闭功能后的延迟窗口创建。
- [x] 将时间敏感与 AppKit 资源属性标记为 `@ObservationIgnored`，不在 `@Observable` 中使用 `@AppStorage`。

### Task 3: 实现多窗口贴图协调器

**Files:**
- Create: `clipaste/Managers/ScreenPinWindowCoordinator.swift`
- Create: `clipaste/Managers/ScreenPinWindowController.swift`
- Create: `clipaste/Views/ScreenPinnedImageView.swift`
- Create: `clipaste/Views/ScreenPinWindowDragView.swift`

- [x] 实现 coordinator 的 `show(image:at:)`、`close(id:)` 和 `closeAll()`，字典持有每张贴图的 controller。
- [x] 实现 `.borderless + .resizable` 的 `NSPanel`，设置 `.floating`、当前 Space 行为、透明背景、阴影、`contentAspectRatio`、`minSize` 和 `maxSize`。
- [x] 使用 `ScreenPinGeometry` 按松开点所在显示器计算初始帧，并在窗口跨显示器移动后刷新最大尺寸。
- [x] `ScreenPinnedImageView` 使用 `Image(nsImage:)` 等比显示原图，右上角常驻本地化的 `xmark` 图标按钮，支持 help 和 VoiceOver。
- [x] `ScreenPinWindowDragView` 仅在图片背景区域调用 `window.performDrag(with:)`，关闭按钮保持更高命中层级。

### Task 4: 实现专用贴图拖拽手柄

**Files:**
- Create: `clipaste/Views/ScreenPinIconDragTarget.swift`
- Create: `clipaste/Views/ScreenPinDragSourceView.swift`
- Modify: `clipaste/Views/ClipboardCardView.swift`
- Modify: `clipaste/Views/ClipboardVerticalItemView.swift`

- [x] 实现仅注册内部 UTI 的 `NSDraggingSession`，使用 `draggingSession(_:endedAt:operation:)` 回传全局屏幕坐标，并禁止失败时回弹动画。
- [x] `ScreenPinIconDragTarget` 复用来源应用图标，提供本地化 help 和辅助功能标签，不新增可见 Pin 按钮。
- [x] 水平卡片、纵向列表和紧凑列表的来源应用图标均可发起贴图拖拽。
- [x] 只在 `ScreenPinViewModel.isEnabled && item.isScreenPinEligible` 时启用图标拖拽，不修改父视图现有 `.onDrag` 行为。
- [x] 将现有 `.onDrag` 限定在普通卡片/列表内容层，再在其外层挂载来源图标透明拖拽区域。

### Task 8: 处理实测反馈：图标入口与稳定缩放

**Files:**
- Create: `clipaste/Models/ScreenPinWindowInteractionPolicy.swift`
- Create: `clipaste/Views/ScreenPinIconDragTarget.swift`
- Create: `scripts/ScreenPinWindowInteractionTests.swift`
- Modify: `clipaste/Managers/ScreenPinWindowController.swift`
- Modify: `clipaste/Views/ScreenPinWindowDragView.swift`
- Modify: `clipaste/Views/ClipboardCardView.swift`
- Modify: `clipaste/Views/ClipboardVerticalItemView.swift`
- Modify: `clipaste/Views/ScreenPinDragSourceView.swift`
- Delete: `clipaste/Views/ScreenPinDragHandle.swift`

- [x] 先添加失败测试，覆盖实时缩放约束延迟、窗口边缘缩放命中和来源应用图标拖拽目标。
- [x] 删除额外 Pin 按钮，将透明贴图拖拽目标覆盖到水平卡片、纵向列表和紧凑列表的来源应用图标上。
- [x] 将窗口四周 8 pt 交还 AppKit 原生缩放，中央区域继续支持窗口移动。
- [x] `inLiveResize` 期间延迟跨屏约束更新，在 `windowDidEndLiveResize` 后统一刷新，避免同步约束重入。
- [x] 为来源应用图标目标提供本地化帮助、VoiceOver 按钮语义、Return/Space 激活和非 Pin 的拖拽预览。
- [x] 运行窗口交互、拖拽命中、几何、ViewModel 与资格测试，完成单实例真实拖拽和连续缩放压力验证。
- [x] 运行七语言 String Catalog 完整性检查与 macOS clean build。

### Task 5: 接入设置、全局环境和操作反馈

**Files:**
- Modify: `clipaste/clipasteApp.swift`
- Modify: `clipaste/Managers/ClipboardPanelManager.swift`
- Modify: `clipaste/Views/ClipboardMainView.swift`
- Modify: `clipaste/Views/AdvancedSettingsView.swift`

- [x] 在 Settings scene 和 Clipboard panel root 注入 `ScreenPinViewModel.shared`。
- [x] 在高级设置的 Interface 分区增加默认关闭的 Toggle 和简短说明，使用 `@Bindable` 绑定 `@Observable` 状态。
- [x] 让 `ClipboardMainView` 在现有 operation notice 位置同时显示贴图加载错误，不新增卡片或模态弹窗。
- [x] 应用终止时调用 `ScreenPinViewModel.closeAll()`，保证会话状态不持久化。

### Task 6: 完成 String Catalog 国际化

**Files:**
- Modify: `clipaste/Localizable.xcstrings`

- [x] 新增源语言键：`Enable Screen Pinning`、`Drag to Pin on Screen`、`Close Pinned Image`、`Couldn't load the image for screen pinning.`。
- [x] 为 `en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`、`de`、`fr` 填写完整翻译，保留用户已有的 `Localizable.xcstrings` 未提交修改。
- [x] 运行 `jq empty clipaste/Localizable.xcstrings` 和 Xcode String Catalog 编译，确认结构有效。

### Task 7: 验证、回归和收口

**Files:**
- Modify: `.trellis/tasks/07-13-screen-pin-drag-compatibility/implement.md`

- [x] 重新运行几何、ViewModel 和生产类型资格测试脚本，确认全部断言通过。
- [x] 运行 `xcodebuild -project clipaste.xcodeproj -scheme Clipaste -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/clipaste-screen-pin-derived clean build -quiet`，确认退出码为 0。
- [x] 检查 `git diff --check`、`git status --short` 和完整 diff，确认未覆盖用户原有未提交修改。
- [x] 对照 PRD 验收每条要求：默认关闭、专用手柄、图片类型限制、多窗口、当前 Space、浮动层级、移动、锁定比例缩放、单张/全部关闭、会话不恢复和七语言文案。

### Task 9: 修复松手坐标并支持原图比例初始尺寸

**Files:**
- Modify: `clipaste/Models/ScreenPinGeometry.swift`
- Modify: `clipaste/ViewModels/ScreenPinViewModel.swift`
- Modify: `clipaste/Managers/ScreenPinWindowCoordinator.swift`
- Modify: `clipaste/Managers/ScreenPinWindowController.swift`
- Modify: `clipaste/Views/ScreenPinDragSourceView.swift`
- Modify: `clipaste/Views/AdvancedSettingsView.swift`
- Modify: `clipaste/Localizable.xcstrings`
- Modify: `scripts/ScreenPinGeometryTests.swift`
- Modify: `scripts/ScreenPinViewModelTests.swift`

- [x] 先添加失败测试，覆盖 25%/100% 原图比例、默认比例、比例持久化、左上角落点和屏幕边缘夹紧。
- [x] 拖拽结束时读取 `NSEvent.mouseLocation`，避免使用可能滞后的会话结束坐标。
- [x] 以松手点作为贴图左上角，仅在越出 `visibleFrame` 时夹紧。
- [x] 高级设置新增 25%–100%、步进 5% 的初始尺寸滑杆，默认 100%，使用 `@Observable` ViewModel 与 `UserDefaults` 持久化。
- [x] 内容控制器安装后重新应用初始窗口帧，修复 1200×800 初始窗口被 SwiftUI 压缩为 160×107。
- [x] 为新增设置标题补齐英语、简中、繁中、日语、韩语、德语和法语；按实测反馈移除两段冗余说明。
- [x] 运行真实鼠标拖拽 harness，确认 Quartz `(500, 500)` 松手对应 AppKit 全局坐标 `(500, 580)`。
- [x] 运行 40 次原生窗口缩放压力测试，窗口保持响应且宽高比保持 1.5。
- [x] 运行全部贴图测试、七语言完整性检查和 macOS clean build。

### Task 10: 清理 SwiftData 快照隔离警告

**Files:**
- Modify: `clipaste/Managers/StorageManager.swift`
- Modify: `.trellis/spec/backend/database-guidelines.md`

- [x] 使用 clean build 复现两个 `makeFromRecord` 主演员隔离警告。
- [x] 确认项目启用了 MainActor-by-default，且两个调用点均位于 SwiftData `@ModelActor` 上下文。
- [x] 将不可变、`Sendable` 的 `ClipboardRecordSnapshot` 显式声明为 `nonisolated`，不跨 actor 传递 SwiftData model。
- [x] 运行警告回归构建，确认两个诊断消失。
- [x] 运行完整 clean build 与贴图回归测试，确认无新增警告或行为回归。
