# 修复分组切换列表横向弹动

## Goal

消除横向剪贴板在切换“全部”、收藏、智能类型和自定义分组时，卡片内容先沿用旧滚动位置、再向新首项横向弹动的视觉问题。

## Root Cause Evidence

- 分组按钮将整个作用域切换包在 spring `withAnimation` 中，使数据源切换与选中样式共用宽泛动画事务（`clipaste/Views/ClipboardHeaderView.swift:932`）。
- 每次分组切换都设置 `shouldResetSelectionToFirstDisplayedItem`（`clipaste/ViewModels/ClipboardViewModel+Groups.swift:225`）。
- 异步筛选结果发布后，选中状态被重置到第一项，并发出非动画滚动请求（`clipaste/ViewModels/ClipboardViewModel+Selection.swift:67`）。
- 横向视图又将该 `scrollTo` 统一推迟到下一次主线程循环（`clipaste/Views/ClipboardHorizontalView.swift:108`），因而用户会先看到新列表沿用旧偏移，再看到首项定位。

## Requirements

- 分组数据作用域切换不得包在 spring 动画事务中；分组 Tab 的选中/悬停样式继续使用自身局部动画。
- 因 `listScrollRequest` 触发的滚动必须在新的列表身份已提交的当前 SwiftUI 更新周期内执行，不得再额外推迟一帧。
- 仅列表初次 `onAppear` 的滚动可以等待一次主演员让出，确保初始布局完成。
- 保留键盘导航的 0.12 秒居中滚动动画，分组切换的首项重置保持无动画。
- 不更改筛选结果、卡片宽度、选中规则、快捷粘贴、自动预览或收藏按钮。
- 不引入新依赖，不新增 `ObservableObject`。

## Acceptance Criteria

- [x] 切换到任意分组后，新内容和首项定位在同一次视图更新内完成，不再出现横向弹动。
- [x] 切换回“全部”时，卡片插入不使用 spring 动画。
- [x] 分组 Tab 的悬停和选中颜色动画保留。
- [x] 键盘方向键切换选中项时，仍使用原有居中滚动动画。
- [x] 回归边界脚本在修复前按预期失败，修复后通过。
- [x] `git diff --check` 与 macOS arm64 Debug clean build 通过。

## Out of Scope

- 不将现有 `ClipboardViewModel` 整体迁移为 Observation。
- 不重写筛选管线或横向卡片容器。
