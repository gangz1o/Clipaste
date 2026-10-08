## 本次更新

本版修复历史较多时自建分组页显示「剪贴板为空」的问题，并修复 iCloud 同步持续失败。

- **分组页显示为空**：历史记录较多时，较早的分组成员（例如从 Paste 迁移来的 Pinboard 条目）不会被加载，分组页显示「剪贴板为空」。现在分组、收藏与类型筛选会直接从数据库读取全部成员。（#63）
- **在分组内搜索**：在分组、收藏或类型筛选下搜索时，较早的匹配记录也能搜到。
- **iCloud 同步失败**：修复自 v2.2.19 起设置页显示「同步失败：CKErrorDomain 错误 2」、新记录无法上传的问题。该问题已在服务端修复，旧版本也会自动恢复同步；同步出错时的提示也更具体。

## What's New

This release fixes empty custom group pages on large histories and the persistent iCloud sync failure.

- **Empty group pages**: With a large history, older group members (such as Pinboard items migrated from Paste) were never loaded, so the group page showed "Clipboard is empty". Group, Favorites and type filters now load all members from the database. (#63)
- **Search inside a group**: Searching within a group, Favorites or a type filter now also finds older matches.
- **iCloud sync failures**: Fixes "Sync failed: CKErrorDomain error 2" and stuck uploads since v2.2.19. The cause is fixed on the server, so older versions resume syncing too; sync error messages are also more specific.

