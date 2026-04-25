# 📋 Clipaste  
[![简体中文](https://img.shields.io/static/v1?label=🇨🇳&message=简体中文&color=red)](README.zh.md) [![English](https://img.shields.io/static/v1?label=🇺🇸&message=English&color=blue)](README.md)


![GitHub Repo stars](https://img.shields.io/github/stars/gangz1o/Clipaste?style=for-the-badge)
<a href="https://github.com/gangz1o/Clipaste/releases/latest"><img src="https://img.shields.io/github/v/release/gangz1o/Clipaste?style=for-the-badge" alt="Latest release"></a>
![GitHub forks](https://img.shields.io/github/forks/gangz1o/Clipaste?style=for-the-badge)
![GitHub contributors](https://img.shields.io/github/contributors/gangz1o/Clipaste?style=for-the-badge)
![GitHub repo size](https://img.shields.io/github/repo-size/gangz1o/Clipaste?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/gangz1o/Clipaste?style=for-the-badge)


Clipaste is a macOS clipboard manager built with **SwiftUI** and **SwiftData**.

Its core goal is simple: **stay fast, smooth, and memory-efficient even when clipboard history becomes large and individual entries become heavy.**

## ✨ Highlights

- 🚀 Fast response across daily interactions
- 🧠 Low memory footprint
- 🗂️ Smooth even with very large clipboard histories
- 📝 Large text entries remain fluid instead of dragging the UI down
- 🐸 Automatically recognizes image content and supports searching
- 🔄 Imports history from **Paste**, **PasteNow**, and **iCopy**
- ↔️ Supports both horizontal and vertical layouts
- ☁️ Optional iCloud / CloudKit sync
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
