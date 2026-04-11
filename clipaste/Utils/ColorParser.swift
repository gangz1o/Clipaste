import SwiftUI
import AppKit

/// 轻量级颜色嗅探引擎，支持从纯文本中识别 HEX / RGB 格式的颜色代码。
/// 严格限制匹配长度，防止误伤普通文章段落。
struct ColorParser {

    /// 从文本中提取颜色。仅当文本内容**完整**匹配已知颜色格式时才返回，否则返回 nil。
    /// - 支持格式：`#RRGGBB`（必须带 # 前缀，6 位）、`rgb(255, 255, 255)`
    nonisolated static func extractColor(from text: String) -> Color? {
        // 去除首尾空格换行，严格限制长度，防止长篇文章误触发
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 25 else { return nil }

        // 1. 嗅探 HEX 颜色：仅接受 #RRGGBB（必须带 #，必须 6 位）
        //    排除：无前缀 / 3 位简写 / 纯数字验证码等误判场景
        let hexPattern = "^#([A-Fa-f0-9]{6})$"
        if trimmed.range(of: hexPattern, options: .regularExpression) != nil {
            let hexSanitized = trimmed.replacingOccurrences(of: "#", with: "")
            var rgb: UInt64 = 0
            Scanner(string: hexSanitized).scanHexInt64(&rgb)
            return Color(
                red:   Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8)  / 255.0,
                blue:  Double( rgb & 0x0000FF)         / 255.0
            )
        }

        // 2. 嗅探 RGB 颜色：rgb(255, 255, 255)
        let rgbPattern = "^rgb\\(\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*\\)$"
        if let regex = try? NSRegularExpression(pattern: rgbPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            let ns = trimmed as NSString
            let rStr = ns.substring(with: match.range(at: 1))
            let gStr = ns.substring(with: match.range(at: 2))
            let bStr = ns.substring(with: match.range(at: 3))
            if let r = Double(rStr), let g = Double(gStr), let b = Double(bStr),
               r <= 255, g <= 255, b <= 255 {
                return Color(red: r / 255.0, green: g / 255.0, blue: b / 255.0)
            }
        }

        return nil
    }
}

// MARK: - WCAG 亮度辅助

extension Color {
    /// 利用 WCAG 2.0 相对亮度公式判断当前颜色是否为深色。
    /// 返回 `true` 时宜叠加白色文字；返回 `false` 时宜叠加黑色文字。
    var isDark: Bool {
        // SwiftUI Color 不直接暴露通道值，需先转为 sRGB 空间的 NSColor
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return false }
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        // WCAG 2.0 相对亮度（人眼对绿色最敏感，蓝色最不敏感）
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.5
    }
}
