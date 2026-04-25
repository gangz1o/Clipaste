# 📋 Clipaste
[![简体中文](https://img.shields.io/static/v1?label=🇨🇳&message=简体中文&color=red)](README.zh.md) [![English](https://img.shields.io/static/v1?label=🇺🇸&message=English&color=blue)](README.md)

![GitHub Repo stars](https://img.shields.io/github/stars/gangz1o/Clipaste?style=for-the-badge)
<a href="https://github.com/gangz1o/Clipaste/releases/latest"><img src="https://img.shields.io/github/v/release/gangz1o/Clipaste?style=for-the-badge" alt="Latest release"></a>
![GitHub forks](https://img.shields.io/github/forks/gangz1o/Clipaste?style=for-the-badge)
![GitHub contributors](https://img.shields.io/github/contributors/gangz1o/Clipaste?style=for-the-badge)
![GitHub repo size](https://img.shields.io/github/repo-size/gangz1o/Clipaste?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/gangz1o/Clipaste?style=for-the-badge)


Clipaste 是一个基于 **SwiftUI** 和 **SwiftData** 构建的 macOS 剪贴板管理器。

它的核心目标很明确：**历史记录再多、文本再大，也要保持响应迅速、滚动丝滑、内存占用可控。**

## ✨ 亮点

- 🚀 响应迅速，常用操作几乎即时完成
- 🧠 内存占用小，长时间运行也更稳定
- 🗂️ 面对超大剪贴板历史仍然保持顺滑不卡顿
- 📝 面对超大文本内容时依然流畅，不会因为内容变重而明显拖慢界面
- 🐸 后台自动ocr识别图片内容，支持搜索图片内文字
- 🔄 可迁移 **Paste**、**PasteNow**、**iCopy** 的历史数据
- ↔️ UI 同时支持横向和纵向布局
- ☁️ 支持可选的 iCloud / CloudKit 同步
- 💕 开源免费

## 🧩 预览
<div align="center">
  <img src="https://cdn.nodeimage.com/i/RgZZ6F1hENt4VtEmYurxED7Dq5esGsNR.webp" width="40%" />
  <img src="https://cdn.nodeimage.com/i/UGNN3td8XU8ruIBNn1I6MdkVDWEoVTs4.webp" width="40%" />
</div>
<br />
<div align="center">
  <img src="https://cdn.nodeimage.com/i/i4Jab3co3VW1kOKL2zEkzIQNsiINGp9p.webp" width="40%" />
  <img src="https://cdn.nodeimage.com/i/jRQP3zlsLV94nuvaoc7Cz781a8u50zVL.webp" width="40%" />
</div>
<br />

## 🏎️ 为什么是 Clipaste

Clipaste 重点解决的是很多剪贴板工具在重负载场景下会暴露的问题：

- 历史记录一多就开始卡
- 大文本一多就开始慢
- 滚动和搜索在重内容场景下不够稳定

Clipaste 的设计目标相反：

- 历史记录很多时仍然保持丝滑
- 大文本内容仍然保持可操作性
- 搜索、预览、再次粘贴保持快速反馈
- 不靠明显增加内存占用来换取表面流畅

如果你用过 Paste 或 PasteNow，Clipaste 的差异点很直接：

- 更强调大历史记录下的性能稳定性
- 更强调大文本内容下的响应速度
- 提供它们没有覆盖到的布局与开源可定制能力

## 🔄 历史迁移

Clipaste 支持从以下应用迁移历史数据：

- Paste
- PasteNow
- iCopy
- Maccy

目标很简单：切换工具时，不需要放弃原有历史记录。


## 🧱 技术栈

- **SwiftUI**：界面构建
- **SwiftData**：存储与迁移
- **CloudKit**：可选同步能力
- 原生 macOS 应用架构

## 🖥️ 系统要求

- macOS 14.0+
- Xcode 16+

## 📦 安装

推荐使用 Homebrew 安装：

```bash
brew tap gangz1o/clipaste
brew install --cask gangz1o-clipaste
```

更新 Clipaste 有两种方式：

- 使用应用内更新
- 通过 Homebrew 更新：

```bash
brew update
brew upgrade --cask gangz1o-clipaste
```

## 🛠️ 本地构建

1. 用 Xcode 打开 `clipaste.xcodeproj`
2. 如果你要在本地运行带 iCloud / Push entitlement 的版本，请选择你自己的签名团队
3. 直接构建运行

如果你 fork 这个项目并准备自行发布，还需要替换你自己的：

- Bundle Identifier
- iCloud Container
- Apple 签名配置

## 🚢 发布

维护者可以通过仓库内的 GitHub Actions 工作流自动生成并上传 notarized DMG，详见 [RELEASING.md](RELEASING.md)。

## 🌟 Star历史

<a href="https://www.star-history.com/?repos=gangz1o%2FClipaste&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
 </picture>
</a>

## 💌 社区交流

有问题、有想法，或者就是想和一群搞开发的人聊聊？

- **论坛**：[linux.do](https://linux.do/) —— 来这里讨论、分享你的配置、反馈问题，欢迎常驻。
