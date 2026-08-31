import Foundation

@main
enum SwiftFileSizeTests {
    private static let maximumLineCount = 300
    private static let allowedOversizedFiles: [String: String] = [:]

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRoots = ["clipaste", "scripts"].map { root.appending(path: $0) }
        var violations: [String] = []

        for sourceRoot in sourceRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let relativePath = fileURL.path.replacing(root.path + "/", with: "")
                let source = try Data(contentsOf: fileURL)
                let lineCount = source.reduce(into: 0) { count, byte in
                    if byte == 0x0A { count += 1 }
                }

                if lineCount > maximumLineCount,
                   allowedOversizedFiles[relativePath] == nil {
                    violations.append("\(relativePath): \(lineCount) lines")
                }
            }
        }

        precondition(
            violations.isEmpty,
            "Swift files exceed \(maximumLineCount) lines without an explicit exception:\n"
                + violations.sorted().joined(separator: "\n")
        )
        print("SwiftFileSizeTests passed")
    }
}
