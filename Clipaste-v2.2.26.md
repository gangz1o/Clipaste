## 本次更新

本版修复连续快速复制后呼出面板卡顿、中间记录丢失的问题，并重新设计了设置页侧边栏。

- **连续复制不再丢记录**：快速连续复制多段内容时，中间的复制可能来不及被记录，只剩最后一条。现在每一次复制都会被完整记录，并按复制顺序排列。（#65）
- **呼出面板不再卡顿**：连续复制后立即用快捷键或菜单栏图标呼出面板，之前可能要卡好几秒才有反应，现在会立即打开。
- **更省资源**：每次复制触发的数据库查询更少，连续复制时后台占用明显降低。
- **全新设置侧边栏**：设置页侧边栏改用系统原生样式，每个设置项配上彩色图标，选中项使用强调色高亮；图标大小跟随系统侧边栏尺寸设置，「关于」的更新提示红点显示在图标上。

## What's New

This release fixes lag and lost history after rapid copying, and redesigns the settings sidebar.

- **No more lost copies**: When copying several items in quick succession, items in the middle could be skipped, leaving only the last one. Every copy is now recorded, in the order you copied it. (#65)
- **Panel opens instantly**: Opening the panel with the shortcut or the menu bar icon right after a burst of copies could hang for several seconds. It now opens right away.
- **Lighter on resources**: Each copy triggers fewer database queries, so bursts of copying use noticeably less background work.
- **Redesigned settings sidebar**: The settings sidebar now uses the native macOS style, with a colored icon for each section and accent-colored selection. Icons follow the system sidebar size setting, and the update badge for "About" now sits on its icon.

