# 实施计划

1. 为链接元数据引擎增加可注入 URLSession 与受限流式读取。
   - 验证：小型 HTML 成功；已知超长与分块超长响应均在预算处停止。
2. 在页面和图标路径应用 MIME、长度与候选数量约束。
   - 验证：非 HTML、超大图标和第 5 个图标候选不会产生有效结果或额外请求。
3. 在 `StorageManager` 合并同一 hash 的在途请求，并让捕获路径遵守 `plain` 模式。
   - 验证：并发重复调用只抓取一次；两条入口在 `plain` 模式均为零请求。
4. 添加定向回归测试或运行时 harness，覆盖正常、超限、取消、去重和偏好门控。
   - 验证：测试命令连续通过，且不访问公网。
5. 运行 macOS Debug 全量构建并检查差异。
   - 验证：`xcodebuild` 成功；所有改动都能追溯到 PRD 验收项。

## Review Gates

- 开发前确认 512 KiB 页面上限、256 KiB 图标上限与最多 4 个图标候选。
- 完成网络 helper 后先运行超限测试，再接入调用门控和去重。
- 若 `URLSession.bytes(for:)` 无法在自定义 `URLProtocol` 下可靠验证取消，改用项目内私有 `URLSessionDataDelegate`，不放宽硬上限。

## Rollback

- 若正常站点兼容性明显下降，保留硬字节上限，只放宽 MIME 未知场景；不得恢复无界 `data(for:)`。
- 不产生 schema 变更，无数据迁移回滚步骤。

## Verification Results

- `LinkMetadataTrafficTests` 连续运行 3 次通过，覆盖正常页面、已知/未知长度超限、错误 MIME、超大 favicon、候选上限和偏好门控。
- 使用 `-strict-concurrency=complete -warn-concurrency` 对相关生产文件与测试 harness 执行类型检查，无警告。
- macOS Debug 构建使用 Xcode 完整工具链与禁用签名配置执行，结果为 `BUILD SUCCEEDED`。
- 最终差异通过 `git diff --check`。
