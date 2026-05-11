import ImageIO
@preconcurrency import Vision

struct OCREngine {
    // 异步提取图片文字，绝不阻塞主线程
    static func extractText(from imageData: Data) async -> String? {
        await Task.detached(priority: .utility) {
            guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                return nil
            }

            let request = VNRecognizeTextRequest()

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
                print("OCR 识别失败: \(error)")
                return nil
            }

            guard let observations = request.results else {
                return nil
            }

            let recognizedText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            return recognizedText.isEmpty ? nil : recognizedText
        }.value
    }
}
