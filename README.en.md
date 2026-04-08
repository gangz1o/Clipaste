# 📋 Clipaste

[简体中文](README.md)

Clipaste is a macOS clipboard manager built with **SwiftUI** and **SwiftData**.

Its core goal is simple: **stay fast, smooth, and memory-efficient even when clipboard history becomes large and individual entries become heavy.**

## ✨ Highlights

- 🚀 Fast response across daily interactions
- 🧠 Low memory footprint
- 🗂️ Smooth even with very large clipboard histories
- 📝 Large text entries remain fluid instead of dragging the UI down
- 🔄 Imports history from **Paste**, **PasteNow**, and **iCopy**
- ↔️ Supports both horizontal and vertical layouts
- ☁️ Optional iCloud / CloudKit sync
- 🆓 Free and open source

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

The goal is simple: switch without losing your existing history.

## 🧩 Preview
![mf7KusniFHeaoGGP4uez83OrVpcSyUIr.webp](https://cdn.nodeimage.com/i/mf7KusniFHeaoGGP4uez83OrVpcSyUIr.webp)
![JuRrDgvz6wfUTptWjEX1uH0zZXiI9Hjs.webp](https://cdn.nodeimage.com/i/JuRrDgvz6wfUTptWjEX1uH0zZXiI9Hjs.webp)
![bu2Tk7GSQ6aRItJc9PpBrEQrJSt4mKGN.webp](https://cdn.nodeimage.com/i/bu2Tk7GSQ6aRItJc9PpBrEQrJSt4mKGN.webp)
![Y3a2gv5YW0T4jHX0GxgKYGyDKPqutJmi.webp](https://cdn.nodeimage.com/i/Y3a2gv5YW0T4jHX0GxgKYGyDKPqutJmi.webp)
![DFLr1a2kN4MJPgoWaCC2CJFvVvyeBgbo.webp](https://cdn.nodeimage.com/i/DFLr1a2kN4MJPgoWaCC2CJFvVvyeBgbo.webp)

## 🧱 Tech Stack

- **SwiftUI** for the interface
- **SwiftData** for storage and migration
- **CloudKit** for optional sync
- Native macOS app architecture

## 🖥️ Requirements

- macOS 14.0+
- Xcode 16+

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
