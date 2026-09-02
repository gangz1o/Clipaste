## ✨ 本次更新

### ⚡ 面板响应与性能

- 修复面板根视图重复创建状态模型引发的 SwiftUI 渲染循环，消除隐藏状态下的异常 CPU 占用及快捷键呼出延迟。
- 剪切板历史改为首屏优先、滚动分页加载，数据量增大后仍能快速呼出面板。
- 集中处理快速粘贴数字键，移除每个卡片单独注册的隐藏快捷键控件，降低视图树和事件路由开销。
- 优化面板显示顺序和动画时长，并移除会触发同步重绘的窗口更新。
- 使用原生日期格式化视图，减少列表滚动和刷新时的格式化成本。

### ✅ 稳定性

- 增加面板状态所有权、分页加载、快速粘贴和展示路径的回归检查。

---

## ✨ What’s New

### ⚡ Panel Responsiveness & Performance

- Fixed a SwiftUI render loop caused by repeatedly constructing the panel state model, eliminating abnormal hidden-state CPU usage and shortcut presentation latency.
- Clipboard history now prioritizes the first screen and loads additional pages on demand, keeping panel presentation fast as history grows.
- Centralized quick-paste number-key routing and removed per-card hidden shortcut controls to reduce view-tree and event-routing overhead.
- Optimized panel presentation ordering and animation timing while avoiding synchronous window redraws.
- Switched timestamps to native date formatting views to reduce list refresh and scrolling work.

### ✅ Stability

- Added regression coverage for panel state ownership, paged history loading, quick paste, and presentation behavior.
