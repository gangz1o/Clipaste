
### 🐛 修复

- 修复 Clipaste 全局注册 `Ctrl + E` 后，导致 macOS 原生 Cocoa 文本快捷键在备忘录、浏览器、终端等应用中失效的问题。

### ✨ 新增

- 新增 Homebrew 安装支持，现可通过 `brew tap gangz1o/clipaste` 和 `brew install --cask gangz1o-clipaste` 安装 Clipaste。
- 新增右键菜单快捷键提示：
  - 收藏操作显示 `Ctrl + E`
  - 预览操作显示 `空格`

### ⚡ 优化

- 优化快捷键作用域：
  - 全局快捷键现在仅用于呼出 / 隐藏 Clipaste 面板
  - 其他快捷键仅在 Clipaste 面板激活时响应，避免与系统和其他应用快捷键冲突
- 优化快捷键设置页的中英文文案与本地化显示。
- 优化右键菜单中的快捷键信息展示与可读性。
- 优化 Homebrew 用户的更新体验，可通过应用内更新或 Homebrew 命令完成升级。

---

### 🐛 Fixed

- Fixed an issue where Clipaste globally capturing `Ctrl + E` would break the native Cocoa “move cursor to end of line” shortcut in apps like Notes, browsers, and Terminal.

### ✨ Added

- Added Homebrew installation support. Clipaste can now be installed with `brew tap gangz1o/clipaste` and `brew install --cask gangz1o-clipaste`.
- Added shortcut hints in the context menu:
  - `Ctrl + E` for Favorites
  - `Space` for Preview

### ⚡ Improved

- Improved shortcut scoping:
  - Global shortcuts are now limited to showing / hiding the Clipaste panel
  - Other shortcuts are only handled when the Clipaste panel is active, avoiding conflicts with system and app shortcuts
- Improved localization and wording in the Shortcuts settings page.
- Improved the visibility and readability of shortcut hints in the context menu.
- Improved the update experience for Homebrew users, with updates available either in-app or through Homebrew.

