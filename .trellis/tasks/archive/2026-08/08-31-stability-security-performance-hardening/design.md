# 技术设计

## 1. 边界与数据流

### 图片

```text
NSPasteboard / file URL
  → ClipboardImageResourcePolicy（字节与像素预算）
  → ImageIO URL/Data source（后台读取 + 下采样）
  → 有界 preview / screen-pin image / OCR image
  → StorageManager
```

统一策略类型只保存常量和纯判断。文件 URL 路径使用 `CGImageSourceCreateWithURL`，避免先构造完整 `Data`。粘贴板已提供的内存数据在进入哈希、缩略图和 OCR 前先检查字节数及图像属性。OCR 只接收下采样后的 `CGImage`。

### 存储切换

```text
freeze monitor
  → drain ClipboardMonitor persistence tasks
  → drain source StorageManager tracked tasks
  → export/import bounded batches
  → atomically activate target runtime
  → resume monitor
```

每次捕获在 MainActor 读取一次当前 `StorageManager` 并传入整个后台流水线。后台代码禁止再次读取 `StorageManager.shared`。普通路由切换只 drain，保留可复用 runtime；删除 iCloud artifacts 的重置路径执行 shutdown、清除强引用并让出一次执行权后再删除。

### 跨库合并

新增固定批次的导出/导入 API。导出使用独立 `ClipboardStoreActor` 和稳定排序/offset；导入只查询当前批次涉及的 hash，避免每批加载整个目标库。分组定义单独合并一次。旧的全量导出仅保留给已证明有界的兼容调用，路由切换不得再使用它。

### AI 密钥

```text
AIConfiguration metadata ──UserDefaults──> no secret
configuration UUID ────────Keychain──────> apiKey
```

`AISecretStore` 协议隔离 Security.framework，生产实现使用 `kSecClassGenericPassword`，测试使用内存实现。Codable 解码暂时接受 legacy `apiKey`；编码永不写出该字段。加载时先写 Keychain，再保存无密钥配置。写入失败保留旧 defaults 数据并显示错误，防止迁移导致密钥丢失。

### 链接地址策略

`LinkMetadataAddressPolicy` 负责 scheme、IP literal 和 DNS 结果分类。生产 resolver 在后台调用系统解析，测试注入确定性地址。`LinkMetadataDataLoader` 在初始请求、重定向和最终响应三个边界调用同一策略。网络 body 仍由现有 delegate 限流。

### SwiftUI 与搜索

`ClipboardRecordSnapshot` 和 `ClipboardItem` 增加 `appIconDominantColorHex`，删除卡片的逐行读取 Task 和 `dominantColorHex()` body fallback。`ClipboardViewModel` 迁移到 Observation 或拆出窄列表状态，使视图只跟踪实际访问属性。

过滤前把 `ClipboardItem` 投影为不含 `NSImage`/`Color` 的 `ClipboardFilterSnapshot`。ViewModel 保存一个可取消 Task；新 generation 先取消旧 Task，后台循环定期检查取消，再在 MainActor 提交 ID。

## 2. 兼容性

- SwiftData schema 不新增必须迁移的持久化字段；主色字段已存在，只扩展 UI 快照。
- AI 配置继续使用原 UserDefaults key，采用读旧写新的就地迁移。
- plain/rich、iCloud、贴图、OCR 和搜索设置键保持不变。
- macOS 14 支持的 Security、ImageIO、SwiftData 和 Swift concurrency API 足够，不新增包依赖。

## 3. 错误与降级

- 超预算文件图片：保留 fileURL 项，不生成 full-image/OCR 派生数据。
- 超预算粘贴板图片：拒绝昂贵处理并记录不含内容的计数诊断。
- 持久化 runtime 失败：优先回退本地，仍失败则使用内存 runtime，并暴露启动错误。
- Keychain 失败：不删除 legacy secret，阻止产生“配置已保存但密钥丢失”的状态。
- DNS 失败或地址非公网：静默跳过自动元数据，诊断只记录原因类别。

## 4. 风险控制

- 存储切换和 AI 迁移先以协议/策略测试锁定顺序，再改生产调用。
- `StorageManager` 全量 API 不直接删除，先迁移高风险调用并通过搜索确认没有遗漏。
- Observation 改造独立验证，若影响范围过大则使用窄行状态适配器达成相同失效隔离，不保留逐卡数据库查询。
- 每个阶段都运行定向测试和 Debug build，发现跨层回归立即停止进入下一阶段。

## 5. 回滚

- 图片策略可单独回滚到仅禁用超预算派生处理，但不得恢复无界文件读取。
- 批次迁移失败时保持源路由激活，目标导入采用现有幂等 hash 合并，允许安全重试。
- Keychain 迁移在确认成功前保留 legacy 值，回滚不会丢失凭据。
- SSRF 策略若误伤站点，只能调整公网地址分类或 DNS 兼容性，不能恢复仅字符串前缀检查。

## 6. 模块化拆分

拆分以现有类型和 extension 的职责为边界：

```text
StorageManager facade
  ├─ task lifecycle / enrichment
  ├─ read facade / export facade
  └─ ClipboardStoreActor
       ├─ record writes
       ├─ group writes
       ├─ maintenance
       ├─ transfer
       └─ mapping / merge helpers

ClipboardRuntimeStore
  ├─ bootstrap / activation
  ├─ route transition / cloud reset
  ├─ maintenance / diagnostics
  └─ favorite recovery / notification observers

SwiftUI feature view
  ├─ owning container
  ├─ independent sections
  └─ reusable controls / presentation helpers
```

跨文件 extension 只访问同一模块内的 `internal` 实现细节；不新增第二份状态，不把数据库模型泄漏给视图，也不引入新的全局单例。自动测试遍历手写 Swift 源文件并强制 300 行上限，显式豁免必须带原因且默认为空。
