import AppKit
@preconcurrency import Vision

struct OCREngine {
    // 异步提取图片文字，绝不阻塞主线程
    static func extractText(from imagePath: String) async -> String? {
        guard let image = NSImage(contentsOfFile: imagePath),
              // 极其关键：Vision 框架需要底层的 CGImage 才能工作
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            // 丢到后台队列去执行，避免卡顿
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                        continuation.resume(returning: nil)
                        return
                    }

                    // 将所有识别到的文本块拼接成一个完整的字符串
                    let recognizedText = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")

                    continuation.resume(returning: recognizedText.isEmpty ? nil : recognizedText)
                }

                // 设定极其强悍的识别配置
                request.recognitionLevel = .accurate
                // 默认支持简体中文、繁体中文和英文混排
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                // 开启语言纠错，提高识别率
                request.usesLanguageCorrection = true

                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try requestHandler.perform([request])
                } catch {
                    print("❌ OCR 识别失败: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
