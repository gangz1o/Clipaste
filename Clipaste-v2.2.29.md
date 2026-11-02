## 本次更新

本版修复复制超大段文字时 Clipaste 卡住、鼠标持续转圈的问题。

- **复制大段文字不再卡顿**：复制很长的文本（例如大型日志或文档全文）时，Clipaste 在判断内容是链接、颜色还是代码时会逐字扫描整段文字，导致界面数秒无响应。现在只分析开头一小段，判断耗时不再随文本长度增长。
- **更准确的类型识别**：以网址开头的超长文本不再被误判为「链接」，会正确归类为文本。

## What's New

This release fixes Clipaste freezing with a spinning cursor after copying very large text.

- **No more freezes on large copies**: When very long text was copied (such as large logs or full documents), Clipaste scanned the entire text to decide whether it was a link, color, or code, leaving the UI unresponsive for several seconds. It now analyzes only the beginning of the text, so classification time no longer grows with its length.
- **More accurate type detection**: Very long text that starts with a URL is no longer misclassified as a link and is correctly treated as text.

