import AVFoundation
import Combine
import Foundation
#if canImport(Speech)
import Speech
#endif
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isSpeechToTextEnabled: Bool = false
    @Published var isTextToSpeechEnabled: Bool = false
    @Published var isSending: Bool = false
    @Published var activeError: Error?
    @Published var accessibilityChecks: [AccessibilityCheck] = []
    @Published var suggestedPrompts: [ChatSuggestion] = []

    private let chatService: ChatService
    private let speechService: SpeechService
    private let swiftDataService: SwiftDataService
    private(set) var conversationId: UUID?

    private var initialContext: String?
    private var retryTask: Task<Void, Never>?
    private var pendingAssistantMessageId: UUID?
    private var cancellables: Set<AnyCancellable> = []

    var retryCount: Int = 0
    let maxRetries: Int = 2

    init(
        chatService: ChatService = .shared,
        speechService: SpeechService = .shared,
        swiftDataService: SwiftDataService = .shared,
        initialContext: String? = nil
    ) {
        self.chatService = chatService
        self.speechService = speechService
        self.swiftDataService = swiftDataService
        self.initialContext = initialContext
        setupSpeechBindings()
        runAccessibilityChecks()
    }

    func onAppear() {
        guard messages.isEmpty else { return }

        if let context = initialContext, !context.isEmpty {
            let systemMessage = ChatMessage(
                role: .assistant,
                text: String(
                    localized: "He detectado: \(context). Déjame explicarte más sobre esto mientras sincronizo con el diagnóstico."
                ),
                metadata: ChatMessageMetadata(isKeyMoment: true)
            )
            messages.append(systemMessage)
            sendInitialContext(context)
        } else {
            messages.append(ChatMessage(
                role: .assistant,
                text: String(localized: "¡Hola! Soy tu Copiloto Káapeh. ¿En qué puedo asistirte hoy?"),
                metadata: ChatMessageMetadata(isKeyMoment: true)
            ))
        }
    }

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""

        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)

        sendToBackend(triggeringMessage: userMessage)
    }

    func sendSuggestion(_ suggestion: ChatSuggestion) {
        inputText = suggestion.text
        sendMessage()
    }

    func retryLastInteraction() {
        guard retryCount < maxRetries, let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            return
        }
        retryCount += 1
        sendToBackend(triggeringMessage: lastUserMessage, allowRetry: true)
    }

    func cancelPendingRequest() {
        retryTask?.cancel()
        retryTask = nil
        isSending = false
        if let pendingId = pendingAssistantMessageId, let index = messages.firstIndex(where: { $0.id == pendingId }) {
            messages[index].status = .failed
            messages[index].text = String(localized: "La solicitud fue cancelada.")
        }
        pendingAssistantMessageId = nil
    }

    func handleSpeechToTextChange(to isEnabled: Bool) {
        if isSpeechToTextEnabled != isEnabled {
            isSpeechToTextEnabled = isEnabled
        }

        if isEnabled {
            speechService.requestAuthorization()
        } else {
            stopRecording()
        }
    }

    func handleTextToSpeechChange(to isEnabled: Bool) {
        if isTextToSpeechEnabled != isEnabled {
            isTextToSpeechEnabled = isEnabled
        }

        if !isEnabled {
            speechService.stopSpeaking()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        guard isSpeechToTextEnabled else { return }
        do {
            try speechService.startRecording { [weak self] transcript in
                guard let self else { return }
                Task { @MainActor in
                    self.inputText = transcript
                }
            }
            isRecording = true
        } catch {
            isRecording = false
            activeError = error
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        speechService.stopRecording()
        isRecording = false
    }

    func speakLastAssistantMessage() {
        guard isTextToSpeechEnabled, let message = messages.last(where: { $0.role == .assistant }) else { return }
        speechService.speak(message.text)
    }

    func markLastAssistantMessageAsKey() {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        do {
            let identifier = conversationId ?? UUID()
            conversationId = identifier
            try swiftDataService.saveKeyConversation(
                conversationId: identifier,
                topic: lastAssistant.text.prefix(60).description,
                entries: messages.map { ChatTranscriptEntry(role: $0.role.rawValue, text: $0.text, timestamp: $0.timestamp, isKeyMoment: $0.metadata.isKeyMoment) }
            )
        } catch {
            activeError = error
        }
    }

    private func sendInitialContext(_ context: String) {
        let contextMessage = ChatMessage(role: .system, text: context)
        messages.append(contextMessage)
        sendToBackend(triggeringMessage: contextMessage)
    }

    private func sendToBackend(triggeringMessage: ChatMessage, allowRetry: Bool = false) {
        retryTask?.cancel()
        isSending = true
        activeError = nil

        // show typing indicator
        let pendingAssistant = ChatMessage(role: .assistant, text: String(localized: "El copiloto está pensando…"), status: .typing)
        messages.append(pendingAssistant)
        pendingAssistantMessageId = pendingAssistant.id

        let transcript = messages
            .filter { message in
                switch message.status {
                case .typing, .failed:
                    return false
                default:
                    return true
                }
            }
            .map { ChatService.MessagePayload(role: $0.role.rawValue, content: $0.text) }

        let conversationReference = conversationId
        retryTask = Task { [weak self] in
            guard let self else { return }
            let startDate = Date()
            do {
                let result = try await self.chatService.sendMessage(
                    conversationId: conversationReference,
                    messages: transcript,
                    context: self.initialContext
                )
                let latency = Date().timeIntervalSince(startDate)
                await MainActor.run {
                    self.conversationId = result.conversationId
                    self.applySuccessResponse(result, latency: latency)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isSending = false
                }
            } catch {
                await MainActor.run {
                    self.applyFailure(error: error, allowRetry: allowRetry)
                }
            }
        }
    }

    private func applySuccessResponse(_ result: ChatService.ChatResult, latency: TimeInterval) {
        guard let pendingId = pendingAssistantMessageId, let index = messages.firstIndex(where: { $0.id == pendingId }) else {
            return
        }

        let newMessage = ChatMessage(
            id: pendingId,
            role: .assistant,
            text: result.message,
            status: .sent,
            timestamp: Date(),
            metadata: ChatMessageMetadata(
                confidence: result.confidence,
                source: result.provider,
                isKeyMoment: result.isKeyMoment,
                suggestions: result.suggestions
            )
        )

        messages[index] = newMessage
        suggestedPrompts = result.suggestions.map { ChatSuggestion(text: $0) }
        isSending = false
        retryCount = 0
        pendingAssistantMessageId = nil
        retryTask = nil

        Task {
            await chatService.sendTelemetry(
                ChatService.TelemetryEvent(
                    conversationId: conversationId ?? result.conversationId,
                    messageId: newMessage.id,
                    latencyMs: Int(latency * 1000),
                    status: "success",
                    provider: result.provider,
                    confidence: result.confidence
                )
            )
        }

        if newMessage.metadata.isKeyMoment {
            do {
                try swiftDataService.saveKeyConversation(
                    conversationId: conversationId ?? result.conversationId,
                    topic: newMessage.text.prefix(60).description,
                    entries: messages.map { ChatTranscriptEntry(role: $0.role.rawValue, text: $0.text, timestamp: $0.timestamp, isKeyMoment: $0.metadata.isKeyMoment) }
                )
            } catch {
                activeError = error
            }
        }

        if isTextToSpeechEnabled {
            speechService.speak(newMessage.text)
        }
    }

    private func applyFailure(error: Error, allowRetry: Bool) {
        isSending = false
        activeError = error
        if let pendingId = pendingAssistantMessageId, let index = messages.firstIndex(where: { $0.id == pendingId }) {
            messages[index].status = .failed
            messages[index].text = String(localized: "No pude obtener respuesta. Intenta de nuevo.")
        }
        pendingAssistantMessageId = nil
        retryTask = nil

        Task {
            await chatService.sendTelemetry(
                ChatService.TelemetryEvent(
                    conversationId: conversationId ?? UUID(),
                    messageId: pendingAssistantMessageId ?? UUID(),
                    latencyMs: 0,
                    status: "error",
                    provider: nil,
                    confidence: nil,
                    errorDescription: error.localizedDescription
                )
            )
        }

        if allowRetry {
            retryLastInteraction()
        }
    }

    private func setupSpeechBindings() {
        speechService.$transcribedText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self, self.isRecording else { return }
                self.inputText = text
            }
            .store(in: &cancellables)
    }

    private func runAccessibilityChecks() {
        accessibilityChecks = [
            AccessibilityCheck(
                title: String(localized: "Contraste mínimo"),
                status: .warning,
                recommendation: String(localized: "Verificar colores en modo luz y oscuro.")
            ),
            AccessibilityCheck(
                title: String(localized: "VoiceOver"),
                status: .pending,
                recommendation: String(localized: "Asegurar etiquetado en botones y mensajes.")
            ),
            AccessibilityCheck(
                title: String(localized: "Dictado disponible"),
                status: SpeechService.isSpeechRecognitionAvailable ? .success : .warning,
                recommendation: String(localized: "Validar reconocimiento de voz en campo ruidoso.")
            ),
            AccessibilityCheck(
                title: String(localized: "Lectura en voz alta"),
                status: SpeechService.isTextToSpeechAvailable ? .success : .warning,
                recommendation: String(localized: "Probar síntesis con diferentes acentos.")
            ),
            AccessibilityCheck(
                title: String(localized: "Tamaño de texto dinámico"),
                status: .pending,
                recommendation: String(localized: "Validar que el chat soporte tamaños XL.")
            )
        ]
    }
}

struct AccessibilityCheck: Identifiable {
    enum Status {
        case pending
        case success
        case warning
        case failure

        var symbolName: String {
            switch self {
            case .pending: return "hourglass"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .pending: return .gray
            case .success: return .green
            case .warning: return .yellow
            case .failure: return .red
            }
        }
    }

    let id = UUID()
    let title: String
    var status: Status
    let recommendation: String
}
