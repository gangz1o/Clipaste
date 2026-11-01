## 本次更新

本版改善 Windows App 远程连接中的粘贴兼容性，并修复文本预览滚动时可能卡死的问题。

- **Windows App 远程粘贴**：修复通过双击历史记录或快捷键粘贴到远程 Windows 时，可能只输入字母 `v` 的问题。针对 Windows App 使用完整的 `Ctrl+V` 按键序列，并等待触发快捷键的修饰键松开、目标应用恢复焦点后再发送。
- **更稳妥的自动粘贴**：统一普通粘贴、纯文本粘贴和 AI 结果粘贴的按键发送逻辑；取消粘贴时释放模拟按键，避免按键残留。
- **文本预览不再卡死**：修复文本预览在滚动临界位置可能陷入布局循环、导致界面无响应的问题。（#66）

## What's New

This release improves pasting into Windows App remote sessions and fixes a text preview freeze during scrolling.

- **Remote paste in Windows App**: Fixes an issue where double-clicking a history item or using a quick-paste shortcut could type only `v` on the remote Windows PC. Clipaste now sends a complete `Ctrl+V` sequence for Windows App, waiting for shortcut modifiers to be released and the target app to regain focus.
- **More robust automatic paste**: Regular paste, plain-text paste, and AI-result paste now share the same keystroke handling. Cancelled sequences release their simulated keys to avoid leaving modifiers held.
- **Text preview freeze fix**: Fixes a layout loop that could make text previews unresponsive near the scrolling boundary. (#66)

