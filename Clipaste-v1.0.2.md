本次更新重点打磨了剪贴板面板的交互体验、启动性能和分组导航表现，让整体使用更顺手、更稳定。

🛠️ 交互修复
- 修复方向键切换历史项时会触发异常音效的问题
- 修复搜索结果中无法使用方向键切换项目的问题
- 优化横版与竖版剪贴板切换体验，减少中间态与闪动感

🚀 性能优化
- 优化启动流程，降低启动阶段的 CPU 与内存占用
- 避免首次打开历史面板时长时间空白，改为更快呈现最近记录并后台补齐完整历史
- 改善面板首次激活时的数据加载节奏，整体响应更轻快

🎛️ 使用体验升级
- 新增“激活面板清空搜索框”开关，打开历史时可自动回到无搜索状态
- 优化分组栏交互，“全部”分组固定显示，不再跟随滚动
- 调整竖版分组栏间距，提升可见分组数量
- 重做分组选中态样式，让顶部导航和整体 UI 更统一

🌍 其他改进
- 补充相关国际化文案
- 持续清理细节表现，提升整体稳定性与一致性

This update focuses on refining the clipboard panel's interaction experience, startup performance, and group navigation, making overall usage smoother and more stable.

🛠️ **Interaction Fixes**
- Fixed an issue where navigating history items with arrow keys triggered abnormal sound effects.
- Fixed an issue where arrow keys could not be used to navigate through search results.
- Optimized the transition between horizontal and vertical clipboard layouts, minimizing intermediate states and flickering.

🚀 **Performance Optimizations**
- Optimized the startup process, reducing CPU and memory consumption during launch.
- Eliminated long blank screens when opening the history panel for the first time; recent records now display instantly while the full history loads in the background.
- Improved the data loading rhythm upon the panel's first activation, resulting in a snappier overall response.

🎛️ **UX Enhancements**
- Added a "Clear search box on panel activation" toggle, allowing the history panel to automatically open in a default, unsearched state.
- Optimized group bar interaction; the "All" group is now pinned and no longer scrolls with other items.
- Adjusted the spacing of the vertical group bar to increase the number of visible groups.
- Redesigned the selected state style for groups to ensure the top navigation aligns more consistently with the overall UI.

🌍 **Other Improvements**
- Added missing localization texts.
- Continued to polish minor visual details to enhance overall stability and consistency.
