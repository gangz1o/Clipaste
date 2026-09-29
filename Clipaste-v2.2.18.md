## 本次更新

- 复制后立即打开面板，最新记录会直接显示，不再延迟两三秒。打开面板时会立即读取剪贴板，后台轮询也不再被系统推迟。
- 面板隐藏时历史会在后台保持最新，打开时首帧即为最新列表，隐藏期间不做界面渲染。
- 降低复制时的后台开销：本地保存不再被当作 iCloud 远端导入处理，每次复制不再额外重载整页和刷新诊断。隐藏时连续复制的 CPU 占用降低约 20–35%。
- 修复启动时的数据维护可能卡住主线程的问题。
- 大幅加快数据维护和开关 iCloud 同步时的数据导出，并降低内存占用：大型数据库上导出从约 23 秒降至 0.14 秒。

## What's New

- Opening the panel right after a copy now shows the new item immediately instead of two to three seconds later. The panel reads the pasteboard when it opens, and background polling is no longer deferred by the system.
- History stays current while the panel is hidden, so the first frame after opening is up to date. Nothing is rendered while the panel is hidden.
- Lower background cost per copy: the app's own saves are no longer handled as iCloud remote imports, so a copy no longer reloads the whole page or refreshes diagnostics. CPU use while copying with the panel hidden is down about 20–35%.
- Fixed startup data maintenance that could hang the main thread.
- Data maintenance and the export that runs when turning iCloud sync on or off are much faster and use less memory: on a large store, export went from about 23s to 0.14s.

