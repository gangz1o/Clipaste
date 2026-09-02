## ✨ 本次更新

### 🛠 启动稳定性

- 修复系统重启后由登录项冷启动时，CloudKit 每次开机初始化与账户查询竞争而导致主线程卡死的问题。
- 启动阶段不再执行仅用于诊断的 CloudKit 账户查询，并确保 CloudKit 可用性检查脱离 MainActor。

### ⚡ 性能

- 仅在按住快速粘贴修饰键时计算条目可见区域，修复面板隐藏时仍持续 SwiftUI 布局循环和高 CPU 占用的问题。
- 松开修饰键时立即清理快速粘贴索引，避免保留陈旧布局状态。

---

## ✨ What’s New

### 🛠 Launch Stability

- Fixed a cold-start hang after system restarts caused by contention between the login-item launch and CloudKit per-boot initialization.
- Removed the diagnostics-only CloudKit account lookup from startup and moved availability checks away from MainActor.

### ⚡ Performance

- Visible-item frames are now measured only while the quick-paste modifier is held, preventing persistent SwiftUI layout loops and high CPU usage while the panel is hidden.
- Quick-paste indexes are cleared as soon as the modifier is released to avoid stale layout state.
