# 实施计划

## Phase A — 建立回归护栏

1. 添加图片资源策略、OCR 像素预算和文件 URL 读取源级测试。
   - 验证：超预算输入失败；生产代码不存在屏幕贴图整文件累积路径。
2. 添加存储切换顺序与固定 storage 捕获测试。
   - 验证：drain/shutdown/delete/activate 顺序可由注入 spy 观察。
3. 添加 Keychain 迁移、endpoint 和地址分类策略测试。
   - 验证：legacy 成功/失败迁移和 IPv4/IPv6/DNS/redirect 矩阵通过。

## Phase B — 崩溃与数据一致性

4. 实现统一图片预算，改为 ImageIO file URL 后台下采样，并让 OCR 使用有界图像。
   - 验证：图片测试、贴图现有测试及内存压力 harness 通过。
5. 让剪贴板捕获固定 StorageManager，跟踪并排空持久化 Task。
   - 验证：切换时旧任务不能访问新 registry；写入完成后才导出。
6. 为 StorageManager 增加 drain/shutdown 生命周期，重排普通切换和 iCloud reset。
   - 验证：旧容器释放前不删除 artifacts，失败后监控和偏好恢复。
7. 用固定批次替换跨路由全量 export/import，并把重复修复改为真实分页。
   - 验证：多批压力测试、收藏/分组/大文本 round-trip 和去重测试通过。
8. 增加持久化初始化的本地/内存降级，移除 `NSScreen.main!`。
   - 验证：注入工厂错误仍产生可用 runtime，显示器为空不崩溃。

## Phase C — 安全

9. 新增 Security.framework Keychain store，迁移 AI 配置并集中验证 endpoint。
   - 验证：UserDefaults 编码不含密钥；创建、编辑、删除、迁移失败路径通过。
10. 新增可注入 DNS resolver 和公网地址策略，覆盖初始、favicon 和重定向请求。
    - 验证：扩展后的 LinkMetadataTrafficTests 连续运行；无公网访问。

## Phase D — SwiftUI 与并发性能

11. 将图标主色放入 SwiftData 快照/ClipboardItem，删除卡片逐行 DB Task 和 body 图片分析。
    - 验证：源码测试拒绝 `loadAppIconDominantColorHex` 卡片调用；两种布局构建。
12. 收紧 ClipboardViewModel 观察边界，避免无关面板状态使全部卡片重算。
    - 验证：Observation/窄状态测试覆盖选择、quick look、拖拽和过滤更新。
13. 用纯 Sendable 快照和可取消 Task 替换 GCD 搜索；修正链接 pending 生命周期。
    - 验证：快速输入压力测试只提交末代结果，旧任务检测取消；失败可按退避重试。
14. 移除纵向滚动额外主队列 hop，分批执行升级维护。
    - 验证：源级回归和列表交互测试通过。

## Phase E — 全量验证与收口

15. 对修改的生产/测试文件运行 `-strict-concurrency=complete -warn-concurrency` 定向类型检查。
16. 运行现有 7 组脚本、新增测试和所有相关 runtime harness。
17. 使用 Xcode 完整工具链执行 macOS Debug clean build，检查 warning。
18. 运行 `git diff --check`、Trellis task validate 和完整差异审计。
19. 更新 `.trellis/spec/`，记录图片预算、存储路由生命周期、Keychain 和 SSRF 新合同。

## Phase F — 大文件模块化

20. 增加 Swift 文件 300 行守门测试并记录当前超限清单。
21. 按 facade、生命周期、查询、维护、迁移和映射职责拆分存储与运行时核心。
22. 按捕获阶段、网络加载、AI 配置/执行职责拆分 manager/service/ViewModel。
23. 把独立 SwiftUI 页面区域和辅助组件提取到独立文件，保持单一状态所有权。
24. 拆分超限测试脚本；最终白名单保持为空，除非有可验证的语言/生成代码限制。
25. 重跑文件规模守门、全部定向回归和严格并发 macOS Debug clean build。

## Review Gates

- Gate 1：图片策略不能通过“后台整文件 Data”伪装成有界加载。
- Gate 2：存储切换测试必须证明 await 顺序，不能只做源码字符串断言。
- Gate 3：Keychain 迁移失败必须保留旧 secret；SSRF 必须验证解析地址和重定向。
- Gate 4：SwiftUI 优化不能通过减少功能或关闭自动预览实现。
- Gate 5：全量构建、严格并发和所有回归测试均通过后才可进入提交阶段。

## Commit Shape

1. `fix: bound image processing and storage transitions`
2. `fix: secure AI credentials and link metadata requests`
3. `perf: narrow clipboard rendering and search work`
4. `docs: codify stability and security boundaries`

提交前按 Trellis Phase 3.4 向用户展示最终文件分组并取得一次确认；不自动 push。

## Verification Results

- 2026-08-31：14/14 组定向回归测试通过，覆盖图片资源边界、存储切换屏障、启动降级、批量传输、AI 密钥与 endpoint、链接元数据网络策略、搜索、收藏恢复和屏幕钉贴。
- 2026-08-31：macOS Debug `clean build` 通过；启用 `-strict-concurrency=complete -warn-concurrency`，构建日志无代码 warning 或 error。
- 2026-08-31：`git diff --check` 与 Trellis task validate 均通过；进入提交确认门。
- 2026-08-31：完成职责拆分后，`SwiftFileSizeTests` 扫描 `clipaste/` 与 `scripts/` 全部通过；手写 Swift 文件最大 299 行，例外白名单为空。
- 2026-08-31：模块化后的 19 组可自动执行回归全部通过；2 个交互式屏幕钉贴 harness 以严格并发参数编译通过。新增搜索取消和 OCR fallback 取消测试。
- 2026-08-31：再次执行严格并发 macOS Debug `clean build`，`CLEAN SUCCEEDED`、`BUILD SUCCEEDED`，无代码 warning 或 error；`git diff --check` 与 Trellis task validate 再次通过。
