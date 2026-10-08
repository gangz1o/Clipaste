## 本次更新

本版修复应用图标在新版 macOS 中缩小、出现双层底板的问题，并包含此前的菜单栏图标、记录置顶与剪贴板提示音改进。

- **修复应用图标尺寸**：使用满幅不透明图稿和原生图标资源，由 macOS 统一处理外轮廓，消除额外灰色底板和过度留白。保留紫色折纸 P 与珊瑚色翻折设计；中英文 README 同步展示系统实际渲染的图标。
- **全新菜单栏图标**：将原剪贴板符号换成与应用图标一致的折纸 P，采用单色矢量资源，自动适配深浅背景，保持小尺寸与 Retina 显示清晰。
- **记录置顶**：右键单条记录即可「置顶 / 取消置顶」，与收藏独立，支持多条记录。横向、纵向和紧凑布局均显示图钉标识，新复制内容排在置顶记录之后；取消置顶后恢复按复制时间排序。解决 #60。
- **置顶持久保存**：重启、分页、搜索和本地 / iCloud 存储切换时保留置顶状态；自动清理与「清空历史」会保留置顶记录。
- **剪贴板变化提示音**：普通系统复制及其他应用更新 Mac 剪贴板时也能播放简短提示音，沿用已有开关偏好，并遵守暂停监听和忽略应用设置。解决 #61。
- **避免重复响铃**：同一次复制不会因手动操作和后台监听而重复播放提示音。

## What's New

This release fixes the undersized, double-tile app icon on newer macOS versions and includes the earlier menu bar icon, pinning and clipboard sound improvements.

- **Fix app icon sizing**: Native icon assets with opaque, full-bleed artwork let macOS apply the outer shape, removing the extra gray tile and excessive padding. The purple folded-paper P and coral fold are preserved. Both READMEs now show the system-rendered icon.
- **New menu bar icon**: A monochrome folded-paper P replaces the old clipboard symbol. The vector template adapts to light and dark backgrounds and stays sharp at small sizes and on Retina displays.
- **Pin records to the top**: Use the context menu to pin or unpin individual records, independently of Favorites. Multiple pins are supported in all three layouts. New copies stay below pinned records; unpinning restores chronological order. Resolves #60.
- **Persistent pins**: Pin state survives restarts, paging, search and local / iCloud store transfers. Automatic cleanup and Clear History preserve pinned records.
- **Clipboard change sound**: Optional sound feedback now also covers ordinary system copies and other applications updating the Mac clipboard. Existing preferences, paused monitoring and ignored applications are respected. Resolves #61.
- **No duplicate sounds**: Manual copying and background monitoring play only one sound for the same clipboard update.

