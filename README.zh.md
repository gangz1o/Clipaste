# 📋 Clipaste
[![简体中文](https://img.shields.io/static/v1?label=🇨🇳&message=简体中文&color=red)](README.zh.md) [![English](https://img.shields.io/static/v1?label=🇺🇸&message=English&color=blue)](README.md)

![GitHub Repo stars](https://img.shields.io/github/stars/gangz1o/Clipaste?style=for-the-badge)
<a href="https://github.com/gangz1o/Clipaste/releases/latest"><img src="https://img.shields.io/github/v/release/gangz1o/Clipaste?style=for-the-badge" alt="Latest release"></a>
![GitHub forks](https://img.shields.io/github/forks/gangz1o/Clipaste?style=for-the-badge)
![GitHub contributors](https://img.shields.io/github/contributors/gangz1o/Clipaste?style=for-the-badge)
![GitHub repo size](https://img.shields.io/github/repo-size/gangz1o/Clipaste?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/gangz1o/Clipaste?style=for-the-badge)


Clipaste 是一套围绕剪贴板设计的工具：Mac 上是剪贴板管理器，iOS 上是一款可以随时切换出来使用的剪贴板键盘。

Mac 端基于 **SwiftUI** 和 **SwiftData** 构建。iOS 端的重点不是再做一个普通的剪贴板 App，而是做成系统键盘：需要粘贴时，像切换输入法或 Emoji 键盘一样切到 Clipaste，选中内容就能继续输入。

它的核心目标很明确：**历史记录再多、文本再大，也要保持响应迅速、滚动丝滑、内存占用可控。** 开启 iCloud 同步后，Mac 客户端和 iOS 键盘可以通过 Apple 的 iCloud / CloudKit 保持连接。

## ✨ 亮点

- 🚀 响应迅速，常用操作几乎即时完成
- 🧠 内存占用小，长时间运行也更稳定
- 🗂️ 面对超大剪贴板历史仍然保持顺滑不卡顿
- 📝 面对超大文本内容时依然流畅，不会因为内容变重而明显拖慢界面
- 🐸 后台自动ocr识别图片内容，支持搜索图片内文字
- 🔄 可迁移 **Paste**、**PasteNow**、**Maccy** 和 **iCopy** 的历史数据
- ↔️ UI 同时支持横向和纵向布局
- ⌨️ iOS 剪贴板键盘，随时从系统键盘里切换出来
- ☁️ Mac 和 iOS 之间支持可选的 iCloud / CloudKit 同步
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

## ⌨️ iOS 剪贴板键盘

Clipaste 的 iOS 版已经正式上架 App Store。它不是一个只能打开查看的剪贴板列表，而是一款第三方键盘：在任何可以输入文字的地方，都可以从系统键盘切换到 Clipaste，直接取用常用内容。

如果你同时使用 Mac 客户端，开启 iCloud 同步后，Mac 上保存的剪贴板历史可以同步到 iOS 键盘里。常用文本、链接、图片都不需要再通过聊天软件或备忘录转一遍，用的时候直接切键盘就行。同步基于 Apple 的 iCloud / CloudKit，使用的是你已经信任的 Apple 账号和系统服务。

iOS 版下载地址：[Clipaste 剪贴板键盘 - App Store](https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055)。这个链接目前是中国区 App Store 地址，其他地区是否自动跳转取决于 Apple 的处理。如果打开不对，也可以直接在你所在地区的 App Store 搜索 `Clipaste` 或 `Clipaste 剪贴板键盘`。

如果 Clipaste 对你有帮助，也欢迎通过 App Store 版支持一下作者，多少补贴一下每年的 Apple Developer 费用。

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

### macOS

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

### iOS / iPadOS

可以在 App Store 安装 [Clipaste 剪贴板键盘](https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055)，也可以直接在你所在地区的 App Store 搜索 `Clipaste` / `Clipaste 剪贴板键盘`。

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
