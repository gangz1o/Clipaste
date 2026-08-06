# 限制链接元数据流量：技术设计

## Problem

`LinkMetadataEngine` 当前通过 `URLSession.data(for:)` 获取页面和 favicon。响应会在 MIME 与大小检查之前完整进入内存；自动重定向可能把普通链接带到大文件 CDN。捕获路径会无条件触发抓取，富链接列表也会补抓缺失元数据，因此同一条记录还可能出现并发请求。

## Boundaries

- `LinkMetadataEngine` 负责 HTTP 响应校验、流式字节预算、候选图标上限与解析。
- `StorageManager` 负责按 `contentHash` 合并在途元数据任务，并沿用现有任务关闭机制。
- `ClipboardMonitor` 与 `ClipboardViewModel` 负责在调用前遵守同一个链接显示偏好。
- SwiftData 模型与 CloudKit schema 保持不变。

## Data Flow

1. 捕获或历史补抓判断当前模式是否为 `rich`。
2. `StorageManager` 在现有任务锁内登记 hash；已登记则直接跳过。
3. `LinkMetadataEngine` 创建请求并取得响应头。
4. 先验证状态码、最终 URL、MIME 和已知长度，再按上限流式读取。
5. 正文解析标题，最多选择 4 个图标 URL；每个图标使用独立的 256 KiB 上限。
6. 成功结果沿用现有 actor 写入；无论成功、失败或取消，都清除在途 hash。

## HTTP Budget

| Resource | Per-request body limit | Attempts |
| --- | ---: | ---: |
| HTML/XHTML | 512 KiB | 1 |
| favicon | 256 KiB | at most 4 |

单条链接在应用层最多消费约 1.5 MiB 响应体。重定向握手和 HTTP 头不计入正文预算，但不会再出现无界正文下载。

## Implementation Shape

在 `LinkMetadataEngine` 内增加一个小型受限读取 helper，接收 `URLSession`、请求、字节上限和响应校验规则。helper 使用 `URLSession.bytes(for:)`，保留底层 task 并在提前退出、超限或取消时显式 `cancel()`。读取第 `limit + 1` 个字节仅用于判定超限，返回成功数据时绝不超过 limit。

`URLSession` 通过默认参数保持生产调用简洁，并允许回归测试传入使用自定义 `URLProtocol` 的 ephemeral session。不会为单一调用引入新的公共网络抽象。

在 `StorageManager` 现有 `taskLock` 保护的数据中加入在途 link hash 集合。登记与任务创建在同一临界区完成，任务 `defer` 清理 hash，避免竞态。

链接显示偏好使用同一个 raw-value key（`linkDisplayMode`）读取，默认值仍为 `rich`。捕获路径和列表路径共用判断函数，避免行为再次分叉。

## Error And Privacy Policy

- 网络失败继续静默降级为无标题/默认图标，不新增用户弹窗。
- 可增加不包含 URL、query、响应内容的 debug 级原因标识；若项目没有既有结构化日志模式，则不新增日志。
- 不保存部分正文或超限图标。
- 不改变现有自动更新、AI 请求或 CloudKit 网络行为。

## Compatibility And Rollback

- macOS 部署目标为 14.0，支持所需的 URLSession async sequence API。
- 服务器缺少 MIME 时保留兼容读取，但仍受硬字节上限约束。
- 回滚只需恢复链接引擎、调用门控和在途集合相关改动；无数据库迁移或数据回滚。

## Validation

- 使用自定义 `URLProtocol`/可注入 session 构造小 HTML、超长正文、错误 MIME、超长图标、取消及重复调用场景。
- 验证 mock 收到的停止事件和已交付字节数，而不依赖公网资源。
- 运行定向测试脚本与完整 Xcode Debug build。
