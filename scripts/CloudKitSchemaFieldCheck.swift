import CoreData
import Foundation
import SwiftData

// Compile with the production SwiftData models; see scripts/check-cloudkit-schema.sh.
enum ClipboardContentType: String { case text, code, image }
enum IconType { case custom, system }
enum IconPickerViewModel { static let customIconNames: Set<String> = [] }

/// 比对 SwiftData 模型与导出的 CloudKit schema（cktool export-schema 的 .ckdb 文本）。
///
/// Production 环境不允许客户端创建字段：模型新增字段而 schema 未部署时，
/// 带新字段的记录上传会被服务端拒绝，表现为 iCloud 导出持续失败（CKError 2 partialFailure）。
@main
enum CloudKitSchemaFieldCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            print("usage: CloudKitSchemaFieldCheck <schema.ckdb>")
            exit(EXIT_FAILURE)
        }

        let schema = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        guard let model = NSManagedObjectModel.makeManagedObjectModel(
            for: [ClipboardRecord.self, ClipboardGroupModel.self, SyncAnchor.self]
        ) else {
            print("❌ 无法从 SwiftData 模型生成 NSManagedObjectModel")
            exit(EXIT_FAILURE)
        }

        var missing: [String] = []
        for entity in model.entities.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
            guard let entityName = entity.name else { continue }
            let recordType = "CD_\(entityName)"
            guard let fields = fieldNames(ofRecordType: recordType, in: schema) else {
                missing.append("\(recordType)（整个记录类型）")
                continue
            }

            for name in entity.attributesByName.keys.sorted() {
                // 外部存储的二进制字段可能只以 _ckAsset 形式存在。
                let field = "CD_\(name)"
                guard fields.contains(field) == false, fields.contains("\(field)_ckAsset") == false else { continue }
                missing.append("\(recordType).\(field)")
            }
        }

        guard missing.isEmpty else {
            print("❌ CloudKit schema 缺少以下字段，带这些字段的记录将无法上传：")
            missing.forEach { print("   - \($0)") }
            print("修复：Debug 包运行 --initialize-cloudkit-schema 上传到 Development，")
            print("再在 CloudKit Console 执行 Deploy Schema Changes 部署到 Production。")
            exit(EXIT_FAILURE)
        }

        print("✅ CloudKit schema 已包含当前模型的全部字段")
    }

    /// 取出 `RECORD TYPE <name> ( ... );` 块里出现的全部 CD_ 字段名。
    static func fieldNames(ofRecordType recordType: String, in schema: String) -> Set<String>? {
        let header = try? NSRegularExpression(
            pattern: "RECORD\\s+TYPE\\s+\"?\(NSRegularExpression.escapedPattern(for: recordType))\"?\\s*\\("
        )
        let fullRange = NSRange(schema.startIndex..., in: schema)
        guard let match = header?.firstMatch(in: schema, range: fullRange),
              let start = Range(match.range, in: schema)?.upperBound else {
            return nil
        }

        let body = schema[start...]
        let block = body.range(of: ");").map { body[..<$0.lowerBound] } ?? body
        let blockText = String(block)
        let fieldPattern = try? NSRegularExpression(pattern: "CD_[A-Za-z0-9_]+")
        let matches = fieldPattern?.matches(in: blockText, range: NSRange(blockText.startIndex..., in: blockText)) ?? []
        return Set(matches.compactMap { Range($0.range, in: blockText).map { String(blockText[$0]) } })
    }
}
