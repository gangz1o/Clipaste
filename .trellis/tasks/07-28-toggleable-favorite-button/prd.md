# 悬停显示的收藏按钮

## Goal

在剪贴板卡片左下角提供一个按需出现的收藏按钮，用户可直接切换当前记录的收藏状态，同时保持界面简洁且与应用主题一致。

## Confirmed Repository Facts

- 横向卡片已在右下角使用 overlay 承载 AI 快捷入口，该入口仅在卡片悬停或选中时显示，快捷粘贴序号优先于 AI 入口（`clipaste/Views/ClipboardCardView.swift:116`, `clipaste/Views/ClipboardCardView.swift:215`, `clipaste/Views/ClipboardCardView.swift:359`）。
- 非紧凑垂直布局也有同样的 AI 悬停/选中显示逻辑，紧凑布局不显示该行内操作（`clipaste/Views/ClipboardVerticalItemView.swift:320`, `clipaste/Views/ClipboardVerticalItemView.swift:348`, `clipaste/Views/ClipboardVerticalItemView.swift:369`）。
- 现有 `pinItem(item:)` 已实现单条记录的收藏/取消收藏切换，并统一通过 `setFavoriteState` 更新内存快照和持久化数据（`clipaste/ViewModels/ClipboardViewModel+Actions.swift:236`, `clipaste/ViewModels/ClipboardViewModel+Actions.swift:599`）。
- 应用主题色由 `AppAccentColor.color` 统一提供，横向和垂直卡片已观察 `appAccentColor` 设置（`clipaste/Models/AppAccentColor.swift:3`, `clipaste/Views/ClipboardCardView.swift:13`, `clipaste/Views/ClipboardVerticalItemView.swift:24`）。
- String Catalog 已包含收藏/取消收藏操作的现有本地化文案，新按钮应复用这些键。

## Requirements

- 在横向剪贴板卡片左下角增加收藏图标按钮。
- 非紧凑垂直列表同步提供收藏行内操作；紧凑布局不显示该按钮，与现有 AI 按钮范围一致。
- 点击未收藏记录的按钮后立即加入收藏；再次点击后立即取消收藏。
- 收藏按钮不常驻；仅在卡片悬停或选中时显示，与现有 AI 按钮的动态显示规则保持一致。
- 不在设置页增加收藏按钮显示/隐藏开关。
- 收藏状态的点击反馈颜色必须跟随当前应用主题色。
- 快捷粘贴修饰键按下时隐藏收藏按钮，避免与快捷粘贴序号的交互意图冲突。
- 点击收藏按钮不得触发“单击粘贴”，但允许现有卡片选中状态正常更新。
- View 仅负责渲染状态和转发交互，收藏切换由现有 Model/ViewModel/Service 边界承担。
- 不引入或更换第三方依赖。

## Acceptance Criteria

- [x] 卡片未悬停且未选中时，收藏按钮不显示。
- [x] 卡片悬停或选中时，左下角显示收藏按钮；移出且取消选中后，按钮消失。
- [x] 非紧凑垂直列表在悬停或选中时显示收藏行内操作，紧凑布局不显示。
- [x] 点击按钮能在收藏/未收藏之间双向切换，状态与现有收藏筛选和持久化逻辑一致。
- [x] 已收藏及按压反馈使用当前主题色，切换主题色后无需重启即可更新。
- [x] 按钮的帮助与辅助功能标签根据当前状态显示“加入收藏”或“取消收藏”，并复用现有本地化。
- [x] 点击按钮在单击粘贴开启时不粘贴卡片内容。
- [x] 现有 AI 按钮、卡片热键、卡片选中与拖拽交互不因新按钮回归。
- [x] String Catalog 结构校验、静态边界检查、`git diff --check` 与 macOS Debug build 通过。

## Out of Scope

- 不重新设计现有收藏筛选、历史记录存储或 AI 功能。
- 不增加第二套收藏数据模型。
- 不在设置页增加新偏好或配置迁移。
