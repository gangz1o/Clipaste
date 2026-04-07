# 📋 Clipaste

Clipaste is a fast, free, open-source clipboard manager for macOS, built with **SwiftUI** and **SwiftData**.

It is designed for people who keep a serious clipboard history and expect the UI to stay responsive even when the dataset gets large.

## ✨ Highlights

- 🚀 Fast response and smooth interaction
- 🧠 Low memory footprint
- 🗂️ Handles very large clipboard histories without stutter
- 📝 Large text entries stay fluid instead of slowing the app down
- 🔄 Imports clipboard history from **Paste**, **PasteNow**, and **iCopy**
- ↔️ Supports both horizontal and vertical layouts
- ☁️ Optional iCloud / CloudKit sync
- 🆓 Free and open source

## 🏎️ Why Clipaste

Clipaste focuses on the problems that start showing up when your clipboard history is no longer small:

- Large histories still scroll smoothly
- Large text payloads remain responsive
- Day-to-day interactions stay immediate
- The UI remains usable without trading away memory efficiency

If you have used Paste or PasteNow before, the main difference is straightforward: Clipaste is built to stay smooth even when the history grows and the content gets heavy.

## 🔄 Migration

Clipaste can migrate existing clipboard history from:

- Paste
- PasteNow
- iCopy

The goal is simple: switch without losing your history.

## 🧱 Tech Stack

- **SwiftUI** for the interface
- **SwiftData** for storage and migration
- **CloudKit** for optional iCloud sync
- Native macOS app architecture

## 🖥️ Requirements

- macOS 14.0+
- Xcode 16+

## 🛠️ Build

1. Open `clipaste.xcodeproj` in Xcode.
2. Select your own signing team if you want to run the app with iCloud / push entitlements.
3. Build and run.

If you are forking this project for your own distribution, you will also need your own:

- Bundle identifier
- iCloud container
- Apple signing configuration

## 🚢 Releases

Maintainers can produce a notarized DMG with the GitHub Actions release workflow described in [RELEASING.md](RELEASING.md).

