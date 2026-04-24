import Foundation

enum ClipboardContentClassifier {
    nonisolated static let repairVersion = 2

    nonisolated static func classify(_ text: String) -> ClipboardContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return .text }

        if ColorParser.isSupportedColorText(trimmed) {
            return .color
        }

        if isLikelyLink(trimmed) {
            return .link
        }

        return isLikelyCode(trimmed) ? .code : .text
    }

    nonisolated static func shouldHighlightAsCode(_ text: String) -> Bool {
        isLikelyCode(text)
    }

    nonisolated static func isLikelyCode(_ text: String) -> Bool {
        let analysis = analyze(text)
        return analysis.hasStrongCodeSignal && analysis.score >= 5
    }

    nonisolated static func isLikelyLink(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }

        return true
    }

    nonisolated private static func analyze(_ text: String) -> Analysis {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return Analysis() }

        let candidate = trimmed.count > 4_000 ? String(trimmed.prefix(4_000)) : trimmed
        let lowercased = candidate.lowercased()
        let tokenSet = Set(tokenize(lowercased))
        let lines = candidate.split(whereSeparator: \.isNewline).prefix(24)

        var analysis = Analysis()
        analysis.keywordHits = tokenSet.intersection(codeKeywords).count

        for token in strongOperatorTokens where candidate.contains(token) {
            analysis.operatorHits += 1
        }

        analysis.hasCodeFence = candidate.contains("```")

        for rawLine in lines {
            let line = String(rawLine)
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.isEmpty == false else { continue }

            analysis.nonEmptyLineCount += 1

            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                analysis.indentedLineCount += 1
            }

            if commentPrefixes.contains(where: { trimmedLine.hasPrefix($0) }) {
                analysis.commentLineCount += 1
            }

            if trimmedLine.hasSuffix("{") || trimmedLine == "}" {
                analysis.braceLineCount += 1
            }

            if trimmedLine.hasSuffix(";") {
                analysis.semicolonLineCount += 1
            }

            if looksLikeAssignmentLine(trimmedLine) {
                analysis.assignmentLineCount += 1
            }

            if looksLikeBulletLine(trimmedLine) {
                analysis.bulletLineCount += 1
            }

            if looksLikeProseLine(trimmedLine) {
                analysis.proseLineCount += 1
            }
        }

        if analysis.hasCodeFence {
            analysis.score += 6
        }

        analysis.score += min(analysis.keywordHits, 3) * 2
        analysis.score += min(analysis.operatorHits, 3) * 2
        analysis.score += min(analysis.commentLineCount, 2) * 3
        analysis.score += min(analysis.assignmentLineCount, 2) * 2
        analysis.score += min(analysis.braceLineCount, 2) * 2
        analysis.score += min(analysis.semicolonLineCount, 2)
        analysis.score += min(analysis.indentedLineCount, 2)

        if analysis.nonEmptyLineCount >= 3 && (analysis.keywordHits > 0 || analysis.operatorHits > 0) {
            analysis.score += 1
        }

        analysis.score -= min(analysis.bulletLineCount, 3) * 2
        analysis.score -= min(analysis.proseLineCount, 3) * 2

        if containsMostlyCJK(candidate),
           analysis.keywordHits == 0,
           analysis.commentLineCount == 0,
           analysis.hasCodeFence == false,
           analysis.assignmentLineCount == 0 {
            analysis.score -= 2
        }

        analysis.hasStrongCodeSignal =
            analysis.hasCodeFence ||
            analysis.keywordHits > 0 ||
            analysis.commentLineCount > 0 ||
            analysis.assignmentLineCount > 0 ||
            analysis.braceLineCount > 0 ||
            analysis.operatorHits >= 2

        return analysis
    }

    nonisolated private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: tokenSeparators).filter { $0.isEmpty == false }
    }

    nonisolated private static func looksLikeAssignmentLine(_ line: String) -> Bool {
        let patterns = [" = ", ":=", " => ", " -> ", "==", "!=", "<=", ">="]
        return patterns.contains(where: line.contains)
    }

    nonisolated private static func looksLikeBulletLine(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return true
        }

        var digitsPrefix = ""
        for char in line {
            if char.isNumber {
                digitsPrefix.append(char)
                continue
            }

            if digitsPrefix.isEmpty == false && (char == "." || char == "、" || char == ")") {
                return true
            }

            break
        }

        return false
    }

    nonisolated private static func looksLikeProseLine(_ line: String) -> Bool {
        let proseMarkers = ["任务", "说明", "要求", "步骤", "架构", "原因", "请", "需要", "实现", "重构"]
        if proseMarkers.contains(where: line.contains) {
            return true
        }

        let sentencePunctuation = ["。", "，", "：", "；", "？"]
        let punctuationHits = sentencePunctuation.reduce(into: 0) { count, marker in
            if line.contains(marker) {
                count += 1
            }
        }

        return punctuationHits >= 2
    }

    nonisolated private static func containsMostlyCJK(_ text: String) -> Bool {
        var cjkCount = 0
        var scalarCount = 0

        for scalar in text.unicodeScalars {
            guard CharacterSet.whitespacesAndNewlines.contains(scalar) == false else { continue }
            scalarCount += 1

            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF:
                cjkCount += 1
            default:
                continue
            }
        }

        guard scalarCount > 0 else { return false }
        return Double(cjkCount) / Double(scalarCount) > 0.35
    }
}

private extension ClipboardContentClassifier {
    struct Analysis {
        var score = 0
        var keywordHits = 0
        var operatorHits = 0
        var commentLineCount = 0
        var braceLineCount = 0
        var semicolonLineCount = 0
        var indentedLineCount = 0
        var assignmentLineCount = 0
        var bulletLineCount = 0
        var proseLineCount = 0
        var nonEmptyLineCount = 0
        var hasCodeFence = false
        var hasStrongCodeSignal = false

        nonisolated init() {}
    }

    nonisolated static let codeKeywords: Set<String> = [
        "async", "await", "case", "catch", "class", "const", "def", "else", "enum", "export",
        "extension", "finally", "for", "func", "function", "guard", "if", "import", "interface",
        "let", "private", "protocol", "public", "return", "select", "struct", "switch", "throw",
        "throws", "try", "typealias", "update", "var", "where", "while"
    ]

    nonisolated static let strongOperatorTokens = [
        "==", "!=", "<=", ">=", "->", "=>", ":=", "::", "&&", "||"
    ]

    nonisolated static let commentPrefixes = ["//", "#include", "#if", "#!", "/*", "* "]

    nonisolated static let tokenSeparators = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "_"))
        .inverted
}
