# 📋 Clipaste  
[![简体中文](https://img.shields.io/static/v1?label=🇨🇳&message=简体中文&color=red)](README.zh.md) [![English](https://img.shields.io/static/v1?label=🇺🇸&message=English&color=blue)](README.md)


![GitHub Repo stars](https://img.shields.io/github/stars/gangz1o/Clipaste?style=for-the-badge)
<a href="https://github.com/gangz1o/Clipaste/releases/latest"><img src="https://img.shields.io/github/v/release/gangz1o/Clipaste?style=for-the-badge" alt="Latest release"></a>
![GitHub forks](https://img.shields.io/github/forks/gangz1o/Clipaste?style=for-the-badge)
![GitHub contributors](https://img.shields.io/github/contributors/gangz1o/Clipaste?style=for-the-badge)
![GitHub repo size](https://img.shields.io/github/repo-size/gangz1o/Clipaste?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/gangz1o/Clipaste?style=for-the-badge)


Clipaste is a clipboard manager for Mac, with an iOS keyboard that keeps your clipboard close wherever you type.

The Mac app is built with **SwiftUI** and **SwiftData**. The iOS app is a keyboard: switch to it from the system keyboard picker, pick a saved clip, and paste without jumping back and forth between apps.

Its core goal is simple: **stay fast, smooth, and memory-efficient even when clipboard history becomes large and individual entries become heavy.** When iCloud sync is enabled, your Mac clipboard history and the iOS keyboard can stay connected through Apple's iCloud / CloudKit.

## ✨ Highlights

- 🚀 Fast response across daily interactions
- 🧠 Low memory footprint
- 🗂️ Smooth even with very large clipboard histories
- 📝 Large text entries remain fluid instead of dragging the UI down
- 🐸 Automatically recognizes image content and supports searching
- 🔄 Imports history from **Paste**, **PasteNow**, **Maccy** and **iCopy**
- ↔️ Supports both horizontal and vertical layouts
- ⌨️ iOS keyboard companion for quick access while typing
- ☁️ Optional iCloud / CloudKit sync between Mac and iOS
- 🆓 Free and open source

## 🧩 Preview
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

## ⌨️ iOS Keyboard

Clipaste for iOS is not just a viewer for your clipboard history. It is a keyboard you can switch to at any time, just like switching between your normal keyboard and emoji keyboard.

With iCloud sync enabled, clips saved on your Mac can appear in the iOS keyboard, so you can reuse text, links, and images without sending them to yourself or keeping another app open. Sync is handled through Apple's iCloud / CloudKit, so it uses the Apple account and system services you already trust.

The iOS app is available on the [App Store](https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055). This link currently points to the China storefront; Apple may redirect it depending on your region. If it does not open correctly, search for `Clipaste` or `Clipaste Clipboard Keyboard` in your local App Store.

If Clipaste is useful to you, the App Store version is also a simple way to support the project and help cover the yearly Apple Developer Program cost.

## 🏎️ Why Clipaste

Clipaste is designed around the failure cases that many clipboard managers start to show under heavier workloads:

- large histories become sluggish
- large text payloads make the UI slow down
- scrolling and searching stop feeling immediate

Clipaste is optimized for the opposite:

- smooth browsing with large histories
- responsive handling of heavy text content
- fast search, review, and re-paste workflows
- strong performance without paying for it with excessive memory usage

If you have used Paste or PasteNow before, the difference is straightforward:

- Clipaste puts more emphasis on performance under larger histories
- Clipaste stays more responsive with heavier text payloads
- Clipaste also gives you layout flexibility and open-source extensibility they do not

## 🔄 Migration

Clipaste can migrate clipboard history from:

- Paste
- PasteNow
- iCopy
- Maccy

The goal is simple: switch without losing your existing history.

## 🧱 Tech Stack

- **SwiftUI** for the interface
- **SwiftData** for storage and migration
- **CloudKit** for optional sync
- Native macOS app architecture

## 🖥️ Requirements

- macOS 14.0+
- Xcode 16+

## 📦 Install

### macOS

Recommended installation method:

```bash
brew tap gangz1o/clipaste
brew install --cask gangz1o-clipaste
```

To update Clipaste, you can either:

- Use the in-app updater
- Update via Homebrew:

```bash
brew update
brew upgrade --cask gangz1o-clipaste
```

### iOS / iPadOS

Install [Clipaste Clipboard Keyboard](https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055) from the App Store, or search for `Clipaste` / `Clipaste Clipboard Keyboard` in your App Store region.

## 🛠️ Build

1. Open `clipaste.xcodeproj` in Xcode
2. Select your own signing team if you want to run the app with iCloud / push entitlements
3. Build and run

If you fork this project and want to distribute your own build, you will also need your own:

- Bundle identifier
- iCloud container
- Apple signing configuration

## 🚢 Releases

Maintainers can generate and upload a notarized DMG using the GitHub Actions workflow documented in [RELEASING.md](RELEASING.md).

## 🌟 Star History

<a href="https://www.star-history.com/?repos=gangz1o%2FClipaste&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
 </picture>
</a>

## 💌 Community

Have questions, ideas, or just want to chat with a community of developers?

- **Forum**: [linux.do](https://linux.do/) — Join the discussion, share your setup, report issues, and stick around.
