import AppKit
import SwiftUI

/// Standalone window content for the image-OCR result. Shows the recognized text in a
/// read-only multi-line editor along with the engine that produced it, plus copy /
/// "retry with other engine" controls.
struct OCRResultView: View {
    let windowID: String
    let imageData: Data
    let sourceTitle: String?

    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue

    @State private var result: OCRResult?
    @State private var isRunning: Bool = false
    @State private var copyToast: String?
    @State private var lastEngineUsed: ImageOCRService.Engine = .auto

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 340)
        .environment(\.locale, appLanguage.resolvedLocale)
        .task {
            await runOCR(.auto)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .foregroundStyle(appAccentColor.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("Recognition Result"))
                    .font(.headline)
                if let sourceTitle, sourceTitle.isEmpty == false {
                    Text(sourceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            engineBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var engineBadge: some View {
        if let result {
            HStack(spacing: 4) {
                Image(systemName: engineIcon(for: result.engine))
                Text(engineLabel(for: result.engine))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - Content

    private var content: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .textBackgroundColor)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice = result?.notice {
                        noticeBanner(notice)
                    }

                    if isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(LocalizedStringKey("Recognizing…"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }

                    if let text = result?.text, text.isEmpty == false {
                        TextEditor(text: .constant(text))
                            .font(.system(size: 13))
                            .scrollDisabled(true)
                            .frame(minHeight: 200)
                    } else if isRunning == false, result != nil {
                        Text(LocalizedStringKey("OCR Found No Text"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.yellow)
            Text(notice)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let copyToast {
                Label(copyToast, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                    .transition(.opacity)
            }

            Spacer()

            Button {
                Task { await retryWithOtherEngine() }
            } label: {
                Label(otherEngineButtonTitle, systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isRunning || result == nil)
            .help(LocalizedStringKey("Retry With Other Engine"))

            Button {
                copy(close: false)
            } label: {
                Text(LocalizedStringKey("Copy"))
            }
            .disabled(isCopyDisabled)

            Button {
                copy(close: true)
            } label: {
                Text(LocalizedStringKey("Copy and Close"))
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCopyDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var otherEngineButtonTitle: LocalizedStringKey {
        switch result?.engine {
        case .ai:
            return LocalizedStringKey("Retry with Vision OCR")
        case .vision, .none:
            return LocalizedStringKey("Retry with AI OCR")
        }
    }

    private var isCopyDisabled: Bool {
        isRunning || (result?.text.isEmpty ?? true)
    }

    // MARK: - Actions

    private func copy(close: Bool) {
        guard let text = result?.text, text.isEmpty == false else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation(.easeInOut(duration: 0.18)) {
            copyToast = String(localized: "Copied")
        }

        if close {
            OCRResultWindowManager.shared.close(windowID: windowID)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                copyToast = nil
            }
        }
    }

    private func runOCR(_ engine: ImageOCRService.Engine) async {
        isRunning = true
        lastEngineUsed = engine
        let result = await ImageOCRService.recognize(imageData: imageData, engine: engine)
        self.result = result
        self.isRunning = false
    }

    private func retryWithOtherEngine() async {
        guard let current = result else { return }
        let next: ImageOCRService.Engine = {
            switch current.engine {
            case .ai: return .vision
            case .vision: return .ai
            }
        }()
        await runOCR(next)
    }

    // MARK: - Helpers

    private func engineLabel(for engine: OCREngineKind) -> String {
        switch engine {
        case .vision:
            return String(localized: "Vision OCR")
        case .ai(let title):
            let format = String(localized: "AI OCR · %@")
            return String(format: format, title)
        }
    }

    private func engineIcon(for engine: OCREngineKind) -> String {
        switch engine {
        case .vision: return "eye"
        case .ai: return "sparkles"
        }
    }
}
