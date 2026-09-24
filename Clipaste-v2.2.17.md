## 本次更新

- 修复开启 iCloud 同步后分组表膨胀的问题：合并本地库时同一分组可能被重复建行。启动后会自动合并重复的已删除分组记录；删除、改名、改图标和排序会作用于同一分组的所有副本，界面按分组去重显示，并修复重复分组下拖动排序可能崩溃的问题。#58
- 迁移导入不再复用已删除的同名分组，避免导入的记录进入看不见的分组。#58

已删除分组会保留一条不可见的删除标记，用于防止其他设备或本地库合并时把它恢复。

## What's New

- Fixed group rows multiplying with iCloud sync enabled: merging the local store could create a second row for the same group. Duplicate deleted-group rows are now merged automatically on launch; delete, rename, icon, and reorder apply to every copy of a group; groups are shown once; and reordering no longer crashes when duplicates exist. #58
- Migration imports no longer reuse a deleted group with the same name, so imported items don't land in hidden groups. #58

Deleted groups keep an invisible deletion marker so other devices or local-store merges can't bring them back.

