### ✨ 本次更新

- 🎨 优化设置页发布版外观，修复 Xcode 运行与 DMG 安装版之间的界面风格差异，让颜色、导航栏和 footer 表现更加统一。
- 🛠️ 调整 Release DMG 构建流程，固定发布环境并增加 Xcode / SDK 校验，减少因 CI 环境变化带来的界面偏差。
- 🍺 修复 Homebrew Tap 更新流程，改为更稳定的 GitHub API 发布方式，避免更新步骤卡住导致 Homebrew 安装版本落后的问题。
- ✅ 提升整体发布稳定性，让 GitHub Release、DMG 和 Homebrew cask 的版本同步更加可靠。

---
### ✨ This Release

- 🎨 Improved the appearance of the packaged Settings window by fixing visual differences between Xcode builds and the distributed DMG, making colors, sidebar styling, and footer layout more consistent.
- 🛠️ Updated the Release DMG pipeline by pinning the build environment and validating the Xcode / SDK version to reduce UI drift caused by CI changes.
- 🍺 Fixed the Homebrew Tap publishing flow by switching to a more reliable GitHub API-based update path, preventing stalled updates that left Homebrew users on outdated versions.
- ✅ Improved overall release stability so GitHub Releases, DMG artifacts, and the Homebrew cask stay in sync more reliably.
