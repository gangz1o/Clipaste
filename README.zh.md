<div align="center">
  <img src="clipaste/Assets.xcassets/AppIcon.appiconset/app-icon-256.png" width="96" alt="Clipaste 应用图标" />

  <h1>Clipaste</h1>

  <p>
    <strong>Mac 剪贴板管理器，现在也有 iOS 剪贴板键盘。</strong>
  </p>

  <p>
    在 Mac 上管理剪贴板历史，在 iOS 输入时随手取用。
  </p>

  <p>
    <a href="README.zh.md">简体中文</a>
    ·
    <a href="README.md">English</a>
  </p>

  <p>
    <a href="https://github.com/gangz1o/Clipaste/releases/latest">
      <img src="https://img.shields.io/github/v/release/gangz1o/Clipaste?style=for-the-badge" alt="Latest release" />
    </a>
    <img src="https://img.shields.io/github/stars/gangz1o/Clipaste?style=for-the-badge" alt="GitHub stars" />
    <img src="https://img.shields.io/github/forks/gangz1o/Clipaste?style=for-the-badge" alt="GitHub forks" />
    <img src="https://img.shields.io/github/issues/gangz1o/Clipaste?style=for-the-badge" alt="GitHub issues" />
  </p>

  <p>
    <a href="#macos-install">下载 macOS 版</a>
    ·
    <a href="https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055">获取 iOS 键盘</a>
    ·
    <a href="https://github.com/gangz1o/Clipaste/releases/latest">最新版本</a>
  </p>
</div>

---

## iOS 剪贴板键盘

Clipaste 的 iOS 版已经正式上架 App Store。它不是一个只能打开查看的剪贴板列表，而是一款第三方键盘：在任何可以输入文字的地方，都可以从系统键盘切换到 Clipaste，直接取用常用内容。

如果你同时使用 Mac 客户端，开启 iCloud 同步后，Mac 上保存的剪贴板历史可以同步到 iOS 键盘里。常用文本、链接、图片都不需要再通过聊天软件或备忘录转一遍，用的时候直接切键盘就行。同步基于 Apple 的 iCloud / CloudKit，使用的是你已经信任的 Apple 账号和系统服务。

iOS 版下载地址：[Clipaste 剪贴板键盘 - App Store](https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055)。这个链接目前是中国区 App Store 地址，其他地区是否自动跳转取决于 Apple 的处理。如果打开不对，也可以直接在你所在地区的 App Store 搜索 `Clipaste` 或 `Clipaste 剪贴板键盘`。

如果 Clipaste 对你有帮助，也欢迎通过 App Store 版支持一下作者，多少补贴一下每年的 Apple Developer 费用。

## 预览

<div align="center">
  <img src="https://cdn.nodeimage.com/i/RgZZ6F1hENt4VtEmYurxED7Dq5esGsNR.webp" width="40%" alt="Clipaste 横向布局预览" />
  <img src="https://cdn.nodeimage.com/i/UGNN3td8XU8ruIBNn1I6MdkVDWEoVTs4.webp" width="40%" alt="Clipaste 纵向布局预览" />
</div>
<br />
<div align="center">
  <img src="https://cdn.nodeimage.com/i/i4Jab3co3VW1kOKL2zEkzIQNsiINGp9p.webp" width="40%" alt="Clipaste 剪贴板内容预览" />
  <img src="https://cdn.nodeimage.com/i/jRQP3zlsLV94nuvaoc7Cz781a8u50zVL.webp" width="40%" alt="Clipaste 设置预览" />
</div>

## Clipaste 能做什么

### iOS 键盘

- 需要取用剪贴板内容时，直接从系统键盘切换到 Clipaste。
- 在 iOS 输入时复用 Mac 上的剪贴板历史。
- 不用打开单独的剪贴板 App，也能粘贴文本、链接和图片。

### Mac 剪贴板管理器

- 常用操作响应迅速，历史记录很多也能保持流畅。
- 支持横向和纵向布局。
- 大文本内容依然可以顺畅预览、搜索和再次粘贴。
- 后台自动 OCR 识别图片内容，支持搜索图片里的文字。
- 支持快速预览、搜索、复制和粘贴。

### 同步与迁移

- 支持 Mac 和 iOS 之间可选的 iCloud / CloudKit 同步。
- 支持迁移 **Paste**、**PasteNow**、**Maccy** 和 **iCopy** 的历史数据。
- 基于原生 SwiftUI 和 SwiftData 架构。
- 开源免费。

## 为什么是 Clipaste

很多剪贴板工具在历史记录变多以后都会慢下来，尤其是内容里有大量文本或图片时，滚动、搜索、预览都会开始拖泥带水。

Clipaste 重点解决的就是这个问题。它更关注真实使用时的速度：历史记录不再小的时候，浏览、搜索、预览和再次粘贴仍然应该是轻快的。

如果你用过 Paste 或 PasteNow，Clipaste 的差异点很直接：它更强调大历史记录下的性能稳定性，也更重视大文本内容下的响应速度，同时保留了布局灵活性和开源可定制能力。

## 历史迁移

Clipaste 支持从以下应用迁移历史数据：

- Paste
- PasteNow
- iCopy
- Maccy

目标很简单：切换工具时，不需要放弃原有历史记录。

## 技术栈

- **SwiftUI**：界面构建
- **SwiftData**：存储与迁移
- **CloudKit**：可选同步能力
- 原生 macOS 应用架构

## 系统要求

- macOS 14.0+
- Xcode 16+

## 安装

<a id="macos-install"></a>

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

### iOS

可以在 App Store 安装 [Clipaste 剪贴板键盘](https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055)，也可以直接在你所在地区的 App Store 搜索 `Clipaste` / `Clipaste 剪贴板键盘`。

## 本地构建

1. 用 Xcode 打开 `clipaste.xcodeproj`。
2. 如果你要在本地运行带 iCloud / Push entitlement 的版本，请选择你自己的签名团队。
3. 直接构建运行。

如果你 fork 这个项目并准备自行发布，还需要替换你自己的：

- Bundle Identifier
- iCloud Container
- Apple 签名配置

## 发布

维护者可以通过仓库内的 GitHub Actions 工作流自动生成并上传 notarized DMG，详见 [RELEASING.md](RELEASING.md)。

## Star 历史

<a href="https://www.star-history.com/?repos=gangz1o%2FClipaste&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
 </picture>
</a>

## 社区交流

有问题、有想法，或者就是想和一群搞开发的人聊聊？

- **论坛**：[linux.do](https://linux.do/) —— 来这里讨论、分享你的配置、反馈问题，欢迎常驻。
