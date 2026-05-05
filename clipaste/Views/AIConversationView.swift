import SwiftUI

struct AIConversationView: View {
    let windowID: String
    let title: String
    let configuration: AIConfiguration

    @State private var messages: [AIChatMessage]
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    init(
        windowID: String,
        title: String,
        configuration: AIConfiguration,
        initialMessages: [AIChatMessage]
    ) {
        self.windowID = windowID
        self.title = title
        self.configuration = configuration
        self._messages = State(initialValue: initialMessages)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            AIConversationMessageBubble(message: message)
                                .id(index)
                        }

                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(LocalizedStringKey("AI is thinking…"))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .padding(.vertical, 8)
                            .id(messages.count)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, newCount in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(max(newCount - 1, 0), anchor: .bottom)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

            composer
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if title.isEmpty {
                    Text(LocalizedStringKey("AI Conversation"))
                        .font(.headline)
                } else {
                    Text(verbatim: title)
                        .font(.headline)
                }
                Text(configuration.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                AIConversationWindowManager.shared.close(windowID: windowID)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 48, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )

            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(LocalizedStringKey("Send"))
        }
        .padding(16)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        draft = ""
        errorMessage = nil
        messages.append(AIChatMessage(role: "user", content: text))
        isSending = true

        let requestMessages = messages
        Task { @MainActor in
            defer { isSending = false }

            do {
                let reply = try await AIExecutionService.shared.send(
                    messages: requestMessages,
                    configuration: configuration
                )
                messages.append(AIChatMessage(role: "assistant", content: reply))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AIConversationMessageBubble: View {
    let message: AIChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(roleTitle, systemImage: roleIcon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(message.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roleTitle: LocalizedStringKey {
        message.role == "assistant" ? "AI" : "You"
    }

    private var roleIcon: String {
        message.role == "assistant" ? "sparkles" : "person"
    }

    private var background: Color {
        message.role == "assistant"
            ? Color(nsColor: .controlBackgroundColor)
            : Color.accentColor.opacity(0.12)
    }
}
