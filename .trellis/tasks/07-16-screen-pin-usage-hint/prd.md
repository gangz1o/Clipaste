# 补充屏幕贴图使用说明

## Goal

在高级设置的“启用屏幕贴图”开关下方增加一条简洁、可直接执行的操作说明，让首次使用者知道需要拖拽图片记录的来源应用图标。

## Requirements

- 说明固定显示在“启用屏幕贴图”开关下方，使用现有设置页的次要说明样式。
- 中文文案为：`按住图片历史记录的来源应用图标，拖到屏幕任意位置后松开，即可生成贴图。`
- 英文源语言键为：`Press and hold the source app icon on an image history item, then drag it anywhere on the screen and release to pin the image.`
- 补齐英语、简体中文、繁体中文、日语、韩语、德语和法语。
- 不恢复已经删除的贴图初始尺寸说明。
- 不修改贴图拖拽、窗口创建、尺寸计算或持久化逻辑。

## Acceptance Criteria

- [x] 高级设置的屏幕贴图开关下方显示一条操作说明。
- [x] 文案明确包含来源应用图标、拖到屏幕任意位置和松开三个动作信息。
- [x] 七种支持语言均存在完整翻译。
- [x] 贴图初始尺寸区域仍只显示标题、百分比和滑杆。
- [x] String Catalog 结构有效，macOS clean build 无警告。
