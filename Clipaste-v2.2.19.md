## 本次更新

- 新增单条记录置顶：右键记录选择「置顶 / 取消置顶」。置顶与收藏独立，支持多条记录，横向、纵向和紧凑布局均显示图钉标识；新复制的内容不会挤走置顶记录。取消置顶后恢复按复制时间排序。解决 #60。
- 置顶状态会持久保存，分页、搜索和本地 / iCloud 存储切换时保留；自动清理和「清空历史」会保留置顶记录。
- 升级「剪贴板变化提示音」开关：普通系统复制及其他应用更新 Mac 剪贴板时也会播放简短提示音，沿用已有开关偏好，并遵守暂停监听和忽略应用设置。解决 #61。
- 避免同一次复制被手动操作和后台监听重复播放提示音。

## What's New

- Pin individual records to the top from the context menu, independently of Favorites. Multiple pins are supported, with pin indicators in horizontal, vertical and compact layouts. New copies stay below pinned records; unpinning restores chronological order. Resolves #60.
- Pins persist across restarts, paging, search and local / iCloud store transfers. Automatic cleanup and Clear History preserve pinned records.
- The Clipboard Change Sound setting now also covers ordinary system copies and other applications updating the Mac clipboard. Existing sound preferences, paused monitoring and ignored applications are respected. Resolves #61.
- Prevented duplicate sounds when a manual copy and clipboard monitoring observe the same update.

## 验证 / Validation

- macOS Release build.
- Pin ordering, pagination, search, persistence and unpin regression tests.
- Sound preference migration and duplicate-sound tests.
- Clipboard capture, retention and store-transfer regression tests.
- Upgrade from the previous database schema preserves existing records and Favorites.

