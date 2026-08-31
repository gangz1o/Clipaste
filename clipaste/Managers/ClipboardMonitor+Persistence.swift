import AppKit
import Foundation
import os

@MainActor
extension ClipboardMonitor {
    func enqueuePersistenceTask(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        let taskID = UUID()
        let task = Task.detached(priority: .utility) {
            await operation()
        }
        persistenceTasks[taskID] = task

        Task { @MainActor [weak self] in
            await task.value
            self?.persistenceTasks.removeValue(forKey: taskID)
        }
    }

    func makeFileURLPayload(
        from pasteboardItem: NSPasteboardItem,
        appID: String?,
        appName: String?,
        sourcePlatformRawValue: String,
        sourceDeviceName: String?,
        captureMethodRawValue: String
    ) -> ClipboardRecordPayload? {
        guard let fileURLString = pasteboardItem.string(forType: fileURLType) else { return nil }

        let fileData = pasteboardItem.data(forType: fileURLType) ?? Data(fileURLString.utf8)
        let contentHash = CryptoHelper.sha256(data: fileData)

        return ClipboardRecordPayload(
            hash: contentHash,
            text: fileURLString,
            appID: appID,
            appName: appName,
            type: ClipboardContentType.fileURL.rawValue,
            rtfData: nil,
            richTextArchive: nil,
            sourcePlatformRawValue: sourcePlatformRawValue,
            sourceDeviceName: sourceDeviceName,
            captureMethodRawValue: captureMethodRawValue,
            captureSessionID: captureSessionID
        )
    }

    func makeTextPayload(
        from pasteboardItem: NSPasteboardItem,
        appID: String?,
        appName: String?,
        sourcePlatformRawValue: String,
        sourceDeviceName: String?,
        captureMethodRawValue: String
    ) -> ClipboardRecordPayload? {
        guard let text = pasteboardItem.string(forType: utf8PlainTextType) ?? pasteboardItem.string(forType: .string) else {
            return nil
        }

        let textData = pasteboardItem.data(forType: utf8PlainTextType) ?? Data(text.utf8)
        let contentHash = CryptoHelper.sha256(data: textData)
        let richTextArchive = ClipboardRichTextArchive.fromPasteboardItem(pasteboardItem)
        let rtfData = richTextArchive?.previewRTFData

        // Excel/WPS 这类结构化表格复制通常带有 HTML/Tabular Text，
        // 这里强制归为普通文本，避免被代码分类器误判为 code。
        let sniffedType: ClipboardContentType
        if richTextArchive?.hasComplexPreviewRepresentations == true {
            sniffedType = .text
        } else {
            // ⚠️ 智能嗅探：在录入瞬间决定数据类型，持久化入库
            sniffedType = Self.sniffTextType(text)
        }

        return ClipboardRecordPayload(
            hash: contentHash,
            text: text,
            appID: appID,
            appName: appName,
            type: sniffedType.rawValue,
            rtfData: rtfData,
            richTextArchive: richTextArchive,
            sourcePlatformRawValue: sourcePlatformRawValue,
            sourceDeviceName: sourceDeviceName,
            captureMethodRawValue: captureMethodRawValue,
            captureSessionID: captureSessionID
        )
    }

    /// 录入期智能嗅探引擎：判断文本的真实语义类型。
    /// 优先级：link → code → text 兜底。
    /// ⚠️ 架构红线：此方法仅在录入时执行一次，结果持久化入库，UI 层绝不做运行时判断。
}
