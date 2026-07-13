#if DEBUG
import CoreData
import Foundation
import SwiftData

/// DEBUG 专用:把当前 SwiftData 模型的完整 schema(含新增字段)上传到
/// CloudKit **Development** 环境。生产环境不允许客户端建字段,所以模型加字段后
/// 必须先跑这个,再到 CloudKit Console 手动 "Deploy Schema Changes to Production"。
///
/// 用法(构建 Debug 包后):
///   Clipaste.app/Contents/MacOS/Clipaste --initialize-cloudkit-schema
///
/// 使用独立的临时 store,不触碰正式数据;成功后进程直接退出。
enum CloudKitSchemaInitializer {
    static let launchArgument = "--initialize-cloudkit-schema"

    static func runIfRequested() {
        guard CommandLine.arguments.contains(launchArgument) else { return }

        // initializeCloudKitSchema 的部分回调派发到主队列;在 run loop 启动前
        // 直接阻塞主线程会造成 30s 超时。改为后台线程执行,主线程泵 run loop。
        let resultBox = SchemaInitializationResultBox()
        Thread.detachNewThread {
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    try initializeDevelopmentSchema()
                    resultBox.set(.success(()))
                    return
                } catch {
                    lastError = error
                    print("⚠️ 第 \(attempt) 次尝试失败: \(error.localizedDescription)")
                    Thread.sleep(forTimeInterval: 2)
                }
            }
            resultBox.set(.failure(lastError ?? SchemaInitializationError.modelConversionFailed))
        }

        while resultBox.get() == nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        switch resultBox.get() {
        case .success:
            print("✅ CloudKit Development schema 初始化完成。")
            print("下一步:打开 https://icloud.developer.apple.com")
            print("→ 选择容器 \(ClipboardModelContainerFactory.cloudKitContainerIdentifier)")
            print("→ Schema → Deploy Schema Changes → 确认部署到 Production。")
            exit(EXIT_SUCCESS)
        case .failure(let error):
            print("❌ CloudKit schema 初始化失败: \(error)")
            exit(EXIT_FAILURE)
        case .none:
            print("❌ CloudKit schema 初始化失败: 未知错误")
            exit(EXIT_FAILURE)
        }
    }

    private static func initializeDevelopmentSchema() throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(
            for: [ClipboardRecord.self, ClipboardGroupModel.self, SyncAnchor.self]
        ) else {
            throw SchemaInitializationError.modelConversionFailed
        }

        let scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipaste-schema-init-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        let storeURL = scratchDirectory.appendingPathComponent("schema.store", isDirectory: false)

        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
        )

        let container = NSPersistentCloudKitContainer(
            name: "ClipasteSchemaInit",
            managedObjectModel: model
        )
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        try container.initializeCloudKitSchema(options: [])
    }

    private enum SchemaInitializationError: LocalizedError {
        case modelConversionFailed

        var errorDescription: String? {
            "无法从 SwiftData 模型生成 NSManagedObjectModel"
        }
    }
}

private final class SchemaInitializationResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func set(_ newResult: Result<Void, Error>) {
        lock.lock()
        result = newResult
        lock.unlock()
    }

    func get() -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
#endif
