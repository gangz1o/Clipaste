## ✨ 本次更新

### 🛡 稳定性与安全

- 为图片解码、屏幕贴图、OCR 与跨库存储迁移增加严格的资源和批次上限，降低大内容导致的卡顿与内存崩溃。
- 修复本地与 iCloud 存储切换、缓存重置期间的任务竞态；持久化初始化失败时可安全降级运行。
- 将 AI API 密钥迁移到 macOS Keychain，并限制不安全的服务端点。
- 完整校验链接元数据请求、DNS 解析和重定向目标，阻断 SSRF 与私网访问。

### ⚡ 性能与架构

- 搜索改为可取消的 Swift Concurrency 任务，减少过期计算和无关 SwiftUI 重绘。
- 移除卡片热路径中的逐项数据库与图片颜色分析。
- 按职责拆分存储、运行时、迁移、服务、ViewModel 和 SwiftUI 组件；所有手写 Swift 文件均不超过 300 行。
- 新增稳定性、安全、并发和文件规模回归守门。

---

## ✨ What’s New

### 🛡 Stability & Security

- Added strict resource and batch limits for image decoding, screen pinning, OCR, and cross-store migration to reduce stalls and memory-pressure crashes.
- Fixed task races during local and iCloud store transitions and cache resets, with safe runtime fallback when persistent storage initialization fails.
- Migrated AI API keys to macOS Keychain and restricted unsafe service endpoints.
- Validated link metadata requests, DNS results, and redirect targets to block SSRF and private-network access.

### ⚡ Performance & Architecture

- Moved search to cancellable Swift Concurrency tasks and narrowed unnecessary SwiftUI invalidation.
- Removed per-item database work and image color analysis from card rendering hot paths.
- Split storage, runtime, migration, services, ViewModels, and SwiftUI views by responsibility; every hand-written Swift file is now at most 300 lines.
- Added regression guards for stability, security, concurrency, and source file size.
