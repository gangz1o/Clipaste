<div align="center">
  <img src="clipaste/Assets.xcassets/AppIcon.appiconset/app-icon-256.png" width="96" alt="Clipaste app icon" />

  <h1>Clipaste</h1>

  <p>
    <strong>A fast clipboard manager for Mac, now with an iOS clipboard keyboard.</strong>
  </p>

  <p>
    Keep your clipboard history on your Mac, and bring it to iOS when you type.
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
    <a href="#macos-install">Download for macOS</a>
    ·
    <a href="https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055" target="_blank">Get iOS Keyboard</a>
    ·
    <a href="https://github.com/gangz1o/Clipaste/releases/latest" target="_blank">Latest Release</a>
  </p>
</div>

---

## iOS Clipboard Keyboard

Clipaste for iOS is a keyboard, not just a clipboard viewer. Switch to it from the system keyboard picker, choose a saved clip, and paste without leaving the app you are typing in.

When iCloud sync is enabled, clips saved on your Mac can appear in the iOS keyboard. Text, links, and images can move with you without sending them to yourself or keeping another app open. Sync uses Apple's iCloud / CloudKit, so it runs through the Apple account and system services you already trust.

<p align="center">
  <a href="https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" height="48" alt="Download on the App Store" />
  </a>
</p>

The App Store badge currently points to the China storefront; Apple may redirect it depending on your region. If it does not open correctly, search for `Clipaste` or `Clipaste Clipboard Keyboard` in your local App Store.

<div align="center">
  <img src="https://is2-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/18/ec/fc/18ecfc6f-93ad-3c44-3399-8b1b3bae2fef/Picsew_20260516140601__U00282_U0029.jpeg/0x0ss.png" width="22%" alt="Clipaste iOS keyboard preview 1" />
  <img src="https://is2-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/3e/8b/f1/3e8bf19e-11e7-c412-c655-641b570fc10b/Picsew_20260516140907__U00281_U0029.jpeg/0x0ss.png" width="22%" alt="Clipaste iOS keyboard preview 2" />
  <img src="https://is2-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/cd/43/7e/cd437e7d-2ded-6e13-1fca-65c9c697257f/Picsew_20260516141233__U00281_U0029.jpeg/0x0ss.png" width="22%" alt="Clipaste iOS keyboard preview 3" />
  <img src="https://is2-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/bd/79/a6/bd79a6c2-e5c1-fd27-1ec2-ad2b2ab64fa4/Picsew_20260516141107__U00281_U0029.jpeg/0x0ss.png" width="22%" alt="Clipaste iOS keyboard preview 4" />
</div>

## Preview

<div align="center">
  <img src="https://cdn.nodeimage.com/i/RgZZ6F1hENt4VtEmYurxED7Dq5esGsNR.webp" width="40%" alt="Clipaste horizontal layout preview" />
  <img src="https://cdn.nodeimage.com/i/UGNN3td8XU8ruIBNn1I6MdkVDWEoVTs4.webp" width="40%" alt="Clipaste vertical layout preview" />
</div>
<br />
<div align="center">
  <img src="https://cdn.nodeimage.com/i/i4Jab3co3VW1kOKL2zEkzIQNsiINGp9p.webp" width="40%" alt="Clipaste clipboard item preview" />
  <img src="https://cdn.nodeimage.com/i/jRQP3zlsLV94nuvaoc7Cz781a8u50zVL.webp" width="40%" alt="Clipaste settings preview" />
</div>

## What Clipaste Does

### iOS Keyboard

- Switch to Clipaste from the iOS keyboard picker whenever you need a saved clip.
- Reuse Mac clipboard history while typing on iOS.
- Paste text, links, and images without opening a separate clipboard app.

### Mac Clipboard Manager

- Fast daily interactions, even with a large clipboard history.
- Smooth horizontal and vertical layouts.
- Responsive handling of large text entries.
- Image text recognition with searchable image content.
- Quick preview, search, copy, and paste workflows.

### Sync & Migration

- Optional iCloud / CloudKit sync between Mac and iOS.
- Migration from **Paste**, **PasteNow**, **Maccy**, and **iCopy**.
- Native SwiftUI and SwiftData architecture.
- Free and open source.

## Why Clipaste

Many clipboard managers start to feel heavy once the history grows, especially when the saved content includes large text payloads or lots of images.

Clipaste is built around that problem. It focuses on staying quick under real use: browsing, searching, previewing, and pasting should still feel immediate when your clipboard history is no longer small.

If you have used Paste or PasteNow before, the difference is straightforward: Clipaste puts more emphasis on large-history performance, keeps heavier text content responsive, and gives you layout flexibility plus open-source extensibility.

## Migration

Clipaste can migrate clipboard history from:

- Paste
- PasteNow
- iCopy
- Maccy

The goal is simple: switch without losing your existing history.

## Tech Stack

- **SwiftUI** for the interface
- **SwiftData** for storage and migration
- **CloudKit** for optional sync
- Native macOS app architecture

## Requirements

- macOS 14.0+
- Xcode 16+

## Install

<a id="macos-install"></a>

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

### iOS

<a href="https://apps.apple.com/cn/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055">
  <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" height="44" alt="Download on the App Store" />
</a>

You can also search for `Clipaste` / `Clipaste Clipboard Keyboard` in your App Store region.

## Build

1. Open `clipaste.xcodeproj` in Xcode.
2. Select your own signing team if you want to run the app with iCloud / push entitlements.
3. Build and run.

If you fork this project and want to distribute your own build, you will also need your own:

- Bundle identifier
- iCloud container
- Apple signing configuration

## Releases

Maintainers can generate and upload a notarized DMG using the GitHub Actions workflow documented in [RELEASING.md](RELEASING.md).

## Star History

<a href="https://www.star-history.com/?repos=gangz1o%2FClipaste&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=gangz1o/Clipaste&type=date&legend=top-left" />
 </picture>
</a>

## Community

Have questions, ideas, or just want to chat with a community of developers?

- **Forum**: [linux.do](https://linux.do/) — Join the discussion, share your setup, report issues, and stick around.
