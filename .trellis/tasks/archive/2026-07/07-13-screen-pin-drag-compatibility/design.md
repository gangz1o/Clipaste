# 屏幕贴图与拖拽兼容技术设计

## 方案结论

采用“来源应用图标贴图拖拽区域”与现有卡片拖拽并存。透明图标命中层启动独立的 AppKit `NSDraggingSession`，在会话结束时取得鼠标的全局屏幕坐标并创建贴图。卡片其他区域仍使用现有 SwiftUI `.onDrag` 和 `ClipboardItem.universalDragProvider`，因此拖到应用、Finder 或 Clipaste 分组的数据类型与行为不变。

## 责任边界

### `ScreenPinViewModel`

- 使用 `@MainActor @Observable`。
- 管理持久化的 `isEnabled`、`initialSizeScale` 和短暂的本地化操作反馈。
- 验证开关和内容类型，异步加载图片数据，把成功结果交给窗口协调器。
- 关闭开关时调用协调器关闭全部贴图。
- 持有并取消尚未完成的贴图加载 `Task`，任务完成前二次检查 `Task.isCancelled` 和 `isEnabled`。
- 不持有 SwiftUI View，不直接构建窗口。

### `ClipboardImagePipeline`

- 复用项目已有的异步图片管线、`NSCache` 和 64 MB `totalCostLimit`，不新增第二套缓存。
- 新增贴图专用方法：剪贴板图片优先读原图再回退预览图，图片文件使用现有文件读取和下采样路径。
- 文件 I/O、ImageIO 尺寸探测和下采样均在已有后台图片队列执行；贴图文件按块读取并在每个阶段检查协作取消标记。
- 缓存键包含 item/file 标识与目标像素尺寸，相同记录的重复贴图共享解码后的 `NSImage`。
- 同键进行中的请求带独立代次 ID；旧请求结束时只能移除自身，开关关闭后返回的旧任务不能覆盖或删除后续新请求。

### `ScreenPinWindowCoordinator`

- `@MainActor` 管理 `[UUID: ScreenPinWindowController]`，支持多窗口、单张关闭和全部关闭。
- 接收已下采样解码的 `NSImage`，使用 `ScreenPinGeometry` 计算初始尺寸、位置、最小与最大尺寸。
- 关闭时先从字典移除 controller，再关闭窗口，避免窗口与图片资源泄漏。

### `ScreenPinWindowController`

- 使用无边框、可缩放的 `NSPanel`，层级为 `.floating`，`hidesOnDeactivate = false`。
- 不设置 `.canJoinAllSpaces` 或 `.moveToActiveSpace`，保持在创建时的 Space。
- 设置 `contentAspectRatio`、`minSize` 和 `maxSize`，保证缩放不变形且不超过当前显示器可见区域。
- 图片中央区域负责移动窗口，四周 8 pt 保留给 AppKit 原生缩放命中；`inLiveResize` 期间跨屏只记录待刷新状态，在 `windowDidEndLiveResize` 后更新尺寸约束。
- 内容使用 `NSHostingController<ScreenPinnedImageView>`。

### SwiftUI View

- `ScreenPinIconDragTarget` 不新增可见图标，只在已有来源应用图标上覆盖工具提示、辅助功能语义和透明 `NSViewRepresentable`。卡片的 `.onDrag` 必须先于图标目标 overlay 应用，防止 SwiftUI 外部拖拽包裹并截获图标的 `mouseDragged` 序列。
- `ScreenPinnedImageView` 只渲染原图和右上角关闭按钮。窗口移动使用透明 `NSViewRepresentable` 调用 `NSWindow.performDrag(with:)`；关闭按钮位于该拖动层之上，保持可点击。
- AppKit 仅用于 SwiftUI 在 macOS 14 上无法提供的拖拽结束坐标和窗口操作。

## 数据流

1. 高级设置的 Toggle 修改 `ScreenPinViewModel.isEnabled`并写入 `UserDefaults`。
2. 支持的图片记录在来源应用图标上启用 `ScreenPinIconDragTarget`，界面不增加额外 Pin 按钮。
3. 按住来源应用图标开始独立拖拽，使用内部 pasteboard UTI，不对外提供图片或文件 URL，因此不会被第三方应用误接收。
4. 拖拽结束回调直接读取 `NSEvent.mouseLocation`，将松手时的实时全局坐标和 `ClipboardItem` 交给 `ScreenPinViewModel`。
5. ViewModel 按当前屏幕像素需求（最长边不超过 4096 px）异步请求共享图片管线；失败时更新本地化 notice，成功时交给 coordinator。
6. Coordinator 在松开点所在 `NSScreen` 中生成贴图窗口，左上角对齐松开点并仅在越界时夹紧到 `visibleFrame`；内容控制器安装完成后重新应用初始帧，避免 SwiftUI 固有尺寸将窗口压到最小值。

## 几何规则

- 外边距：12 pt。
- 初始比例：原图的 25%–100%，步进 5%，默认 100%，由 `UserDefaults` 持久化。
- 初始最大范围：当前 `visibleFrame` 减去双边 12 pt 外边距。
- 过小图片：等比放大，使最长边至少为 240 pt，但不超过可见范围。
- 最小缩放：最长边 160 pt，极端宽高比时优先保持宽高比与屏幕可容纳性。
- 最大缩放：当前显示器 `visibleFrame` 减去双边 12 pt 外边距。

## 兼容与错误处理

- 开关默认值为 `false`，升级无迁移副作用。
- 无法读取原图、预览图或图片文件时，不创建窗口，在历史面板显示本地化 notice。
- 关闭原始历史面板不影响已创建贴图；关闭贴图开关或退出应用会关闭全部贴图。
- 原始图片记录被删除或原始文件随后失效，不影响已创建贴图；贴图窗口持有当次已加载的 `NSImage`。

## 性能与资源策略

- 主演员上只读取 `NSScreen` 信息、修改 Observation 状态和创建/销毁 AppKit 窗口，不进行文件读取或图片解码。
- 对原图使用 ImageIO 下采样，目标像素尺寸由最大可见贴图尺寸与屏幕 backing scale 推导，并上限为 4096 px。
- 现有 `ClipboardImagePipeline` 的缓存计数上限 256、成本上限 64 MB 继续生效；成本按解码后的像素宽高乘 4 计算，避免 JPEG 等压缩源低估内存；内存压力下未被窗口持有的缓存项可由 `NSCache` 淘汰。
- 每张打开的贴图只持有一个下采样后的 `NSImage`；关闭后 coordinator 立即断开持有链。
- 开关关闭或应用终止时先取消 pending tasks，再销毁窗口，避免延迟回调重新创建贴图。

## 验证

- 使用独立 Swift 测试脚本对 `ScreenPinGeometry` 进行红-绿验证：原图比例初始尺寸、左上角落点、宽高比、多屏幕夹紧、最小/最大尺寸。
- 使用 window-backed 命中测试和运行时拖拽 harness 验证专用 AppKit 拖拽源可收到完整按下、拖动、松开事件，并与父级 `.onDrag` 隔离。
- 使用 `xcodebuild -project clipaste.xcodeproj -scheme Clipaste -configuration Debug build` 验证完整编译。
- 人工检查水平、纵向、紧凑布局，并验证普通拖拽、内部分组拖拽和专用贴图拖拽互不干扰。
