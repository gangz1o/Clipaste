import Foundation

enum ClipboardContentType: String {
    case text, image, fileURL, color, link, code
}

@main
enum ClipboardContentClassifierTests {
    static func main() {
        // 小文本的分类结果保持不变。
        precondition(ClipboardContentClassifier.classify("#1E90FF") == .color)
        precondition(ClipboardContentClassifier.classify("rgb(30, 144, 255)") == .color)
        precondition(ClipboardContentClassifier.classify("https://example.com/path?q=1") == .link)
        precondition(ClipboardContentClassifier.classify("let value = compute()\nreturn value") == .code)
        precondition(ClipboardContentClassifier.classify("今天下午三点开会，请大家准时参加。") == .text)
        precondition(ClipboardContentClassifier.isLikelyLink("https://example.com"))

        // 剪贴板读出的是桥接 NSString，逐字遍历极慢；录入在主线程上分类，必须与全文长度无关。
        let paragraph = "The quick brown fox jumps over the lazy dog, 然后继续写一段中文内容。\n"
        let hugeText = NSMutableString(string: "https://example.com/" + String(repeating: paragraph, count: 800_000)) as String
        let hugeCode = NSMutableString(string: String(repeating: "let value = compute() // note\n", count: 2_000_000)) as String
        // 首次访问可变 NSString 会做一次不可变拷贝；剪贴板给的是不可变串，没有这笔开销，计时前先摊掉。
        _ = hugeText.utf16.count + hugeCode.utf16.count

        let start = Date()
        let hugeTextType = ClipboardContentClassifier.classify(hugeText)
        let hugeCodeType = ClipboardContentClassifier.classify(hugeCode)
        let isHugeLink = ClipboardContentClassifier.isLikelyLink(hugeText)
        let elapsed = Date().timeIntervalSince(start)

        precondition(hugeTextType == .text, "Oversized text must not be classified as a link")
        precondition(hugeCodeType == .code, "Oversized code is still detected from its prefix")
        precondition(isHugeLink == false)
        precondition(elapsed < 0.05, "Classifying oversized text took \(elapsed)s")
        print("ClipboardContentClassifierTests passed (\(String(format: "%.3f", elapsed))s)")
    }
}
