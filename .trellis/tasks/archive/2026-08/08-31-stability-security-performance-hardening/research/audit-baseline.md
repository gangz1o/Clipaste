# 审计基线

## 版本范围

- v2.1.8：后台历史窗口、数据库搜索补充和图标缓存相关改动。
- v2.2.2：超大文本和同步策略扩大了记录载荷。
- v2.2.3–v2.2.4：屏幕贴图增加文件图片读取路径。
- v2.2.7：收藏恢复重写部分 store export/import。
- v2.2.8–v2.2.10：富链接流量约束和图标 fallback。

## 已确认代码证据

1. `ClipboardImagePipeline.loadScreenPinFileDataOffMain` 把 1 MiB chunk 持续追加到无上限 `Data`。
2. `ClipboardFileReference.accessibleData` 使用无上限 `Data(contentsOf:)`，且文件捕获入口位于 `@MainActor ClipboardMonitor`。
3. `OCREngine` 使用 `CGImageSourceCreateImageAtIndex` 解码完整分辨率。
4. `ClipboardMonitor` 后台流水线在多个 await 之间反复解析 `StorageManager.shared`。
5. `ClipboardRuntimeStore.rebuildRuntime` 未 drain/shutdown 源 storage；iCloud reset 在旧容器可能存活时删除 artifacts。
6. `StorageManager.exportStore` 和 `makeRecordExport` 一次物化全部记录及 external-storage 字段。
7. `AIConfiguration` Codable 包含 apiKey，`AISettingsViewModel.save` 将其写入 UserDefaults。
8. `LinkMetadataEngine.shouldSkip` 只检查少数 hostname 字符串前缀，未校验 DNS 地址。
9. `ClipboardCardView` 在 body fallback 中分析图标颜色，并为每行启动主色数据库读取。
10. `ClipboardViewModel` 有 26 个 `@Published` 属性，被多种行视图整体观察；过滤使用不可取消 GCD，并传递含 NSImage/Color 的 `@unchecked Sendable ClipboardItem`。
11. 重复记录修复注释声称 batched，实际全表 fetch；纵向滚动仍有额外 main queue hop。

## 初始验证

- macOS Debug build：成功。
- `LinkMetadataTrafficTests`、`ClipboardSearchSupplementPolicyTests`、`FavoriteCloudRecoverySourceTests`、屏幕贴图几何/资格/ViewModel/窗口测试：全部通过。
- 本机 DiagnosticReports 未发现 Clipaste crash/ips 文件，因此崩溃原因以代码证据和内存/竞态风险排序，实施后需要新增压力验证。

## 规模与耦合指标

- `StorageManager.swift`：2056 行。
- `ClipboardRuntimeStore.swift`：1650 行。
- ClipboardViewModel 及扩展：约 2729 行，26 个 `@Published`。
- `StorageManager.shared`：73 处调用，分布于 19 个 Swift 文件。

这些指标不单独构成缺陷，但解释了为什么存储路由、派生任务和 UI 状态变化会跨层放大。
