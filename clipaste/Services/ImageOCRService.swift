import Foundation

/// Engine that produced the OCR text shown to the user.
enum OCREngineKind: Equatable {
    /// Apple Vision framework (fully on-device).
    case vision
    /// Multimodal AI configuration; the associated value is the configuration's display title.
    case ai(configurationTitle: String)
}

/// Outcome of an OCR run: the recognized text plus metadata describing which engine
/// actually produced the result and any human-readable notice (e.g. "AI failed, fell back to Vision").
struct OCRResult: Equatable {
    /// Recognized text (may be empty if neither engine could find any).
    let text: String
    /// The engine that produced `text`.
    let engine: OCREngineKind
    /// Optional one-line notice explaining anything the user should know
    /// (model not multimodal, AI failed and fell back, etc.).
    let notice: String?
}

/// Single entry point for image OCR. Picks the engine according to AI settings and
/// falls back to Vision OCR whenever AI is not eligible or fails.
enum ImageOCRService {
    enum Engine {
        case auto
        case vision
        case ai
    }

    /// Run OCR using the user's preferred engine and return both the text and
    /// metadata describing what actually happened. Never throws — failures get
    /// surfaced through the `notice` field.
    @MainActor
    static func recognize(imageData: Data, engine: Engine = .auto) async -> OCRResult {
        let settings = AISettingsViewModel.shared
        let activeConfig = settings.activeConfiguration

        let resolvedEngine: Engine = {
            switch engine {
            case .auto:
                return settings.isAIEnabled && settings.isAIOCREnabled ? .ai : .vision
            default:
                return engine
            }
        }()

        if resolvedEngine == .ai {
            guard let activeConfig else {
                guard Task.isCancelled == false else { return cancelledResult }
                let text = await runVision(imageData: imageData)
                return OCRResult(
                    text: text,
                    engine: .vision,
                    notice: String(localized: "AI OCR Requires Configuration")
                )
            }

            if activeConfig.supportsImage == false {
                guard Task.isCancelled == false else { return cancelledResult }
                let text = await runVision(imageData: imageData)
                return OCRResult(
                    text: text,
                    engine: .vision,
                    notice: String(localized: "Current Model Does Not Support Images Notice")
                )
            }

            let result = await OCRFallbackCoordinator.run(
                primary: {
                    let text = try await AIExecutionService.shared.runVisionOCR(
                        imageData: imageData,
                        configuration: activeConfig
                    )
                    return OCRResult(
                        text: text,
                        engine: .ai(configurationTitle: activeConfig.displayTitle),
                        notice: nil
                    )
                },
                fallback: { error in
                    let text = await runVision(imageData: imageData)
                    let format = String(localized: "AI OCR Failed Fallback Notice %@")
                    let notice = String(format: format, error.localizedDescription)
                    return OCRResult(text: text, engine: .vision, notice: notice)
                }
            )
            return result ?? cancelledResult
        } else {
            guard Task.isCancelled == false else { return cancelledResult }
            let text = await runVision(imageData: imageData)
            return OCRResult(text: text, engine: .vision, notice: nil)
        }
    }

    private static var cancelledResult: OCRResult {
        OCRResult(text: "", engine: .vision, notice: nil)
    }

    private static func runVision(imageData: Data) async -> String {
        await OCREngine.extractText(from: imageData) ?? ""
    }
}
