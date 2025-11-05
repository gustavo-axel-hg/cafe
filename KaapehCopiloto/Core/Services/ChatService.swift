import Foundation

/// `ChatService` encapsula la comunicación con el backend/LLM provider.
///
/// API Contract v1:
/// ```json
/// POST /api/v1/chat
/// {
///   "conversationId": "UUID?",
///   "messages": [{"role": "user|assistant|system", "content": "..."}],
///   "context": {"initialIssue": "String?", "language": "es-MX", "channel": "ios"},
///   "metadata": {"appVersion": "1.0", "timezone": "America/Mexico_City", "capabilities": ["chat", "speech_to_text"]}
/// }
///
/// Response:
/// {
///   "conversationId": "UUID",
///   "message": {"id": "UUID", "role": "assistant", "content": "..."},
///   "metadata": {"provider": "openai", "latencyMs": 1234, "confidence": 0.82, "isKeyMoment": true, "suggestions": ["..."]},
///   "usage": {"promptTokens": 123, "completionTokens": 456, "totalTokens": 579}
/// }
/// ```
///
/// Telemetry hook:
/// ```json
/// POST /api/v1/chat/events
/// {
///   "conversationId": "UUID",
///   "messageId": "UUID",
///   "latencyMs": 1200,
///   "status": "success|error",
///   "provider": "openai",
///   "confidence": 0.82,
///   "errorDescription": "String?"
/// }
/// ```
struct ChatService {
    static let shared = ChatService()

    struct MessagePayload: Codable {
        let role: String
        let content: String
    }

    struct ChatContext: Codable {
        let initialIssue: String?
        let language: String
        let channel: String

        init(initialIssue: String?, language: String = Locale.current.identifier, channel: String = "ios") {
            self.initialIssue = initialIssue
            self.language = language
            self.channel = channel
        }
    }

    struct RequestMetadata: Codable {
        let appVersion: String
        let timezone: String
        let capabilities: [String]

        init(appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev", capabilities: [String] = []) {
            self.appVersion = appVersion
            self.timezone = TimeZone.current.identifier
            self.capabilities = capabilities
        }
    }

    struct ChatRequest: Codable {
        let conversationId: UUID?
        let messages: [MessagePayload]
        let context: ChatContext
        let metadata: RequestMetadata
    }

    struct ChatResponse: Codable {
        struct AssistantMessage: Codable {
            let id: UUID
            let role: String
            let content: String
        }

        struct Usage: Codable {
            let promptTokens: Int
            let completionTokens: Int
            let totalTokens: Int
        }

        struct ResponseMetadata: Codable {
            let provider: String
            let latencyMs: Int
            let confidence: Double?
            let isKeyMoment: Bool?
            let suggestions: [String]?
        }

        let conversationId: UUID
        let message: AssistantMessage
        let metadata: ResponseMetadata
        let usage: Usage?
    }

    struct ChatResult {
        let conversationId: UUID
        let message: String
        let provider: String
        let confidence: Double?
        let isKeyMoment: Bool
        let suggestions: [String]
    }

    struct TelemetryEvent: Codable {
        let conversationId: UUID
        let messageId: UUID
        let latencyMs: Int
        let status: String
        let provider: String?
        let confidence: Double?
        let errorDescription: String?

        init(
            conversationId: UUID,
            messageId: UUID,
            latencyMs: Int,
            status: String,
            provider: String?,
            confidence: Double?,
            errorDescription: String? = nil
        ) {
            self.conversationId = conversationId
            self.messageId = messageId
            self.latencyMs = latencyMs
            self.status = status
            self.provider = provider
            self.confidence = confidence
            self.errorDescription = errorDescription
        }
    }

    private let network: NetworkService

    init(network: NetworkService = .shared) {
        self.network = network
    }

    func sendMessage(
        conversationId: UUID?,
        messages: [MessagePayload],
        context: String?
    ) async throws -> ChatResult {
        let payload = ChatRequest(
            conversationId: conversationId,
            messages: messages,
            context: ChatContext(initialIssue: context, language: Locale.preferredLanguages.first ?? "es-MX"),
            metadata: RequestMetadata(capabilities: availableCapabilities())
        )

        let response: ChatResponse = try await network.post(endpoint: "/chat", body: payload)
        return ChatResult(
            conversationId: response.conversationId,
            message: response.message.content,
            provider: response.metadata.provider,
            confidence: response.metadata.confidence,
            isKeyMoment: response.metadata.isKeyMoment ?? false,
            suggestions: response.metadata.suggestions ?? []
        )
    }

    @discardableResult
    func sendTelemetry(_ event: TelemetryEvent) async -> Bool {
        do {
            let _: EmptyResponse = try await network.post(endpoint: "/chat/events", body: event)
            return true
        } catch {
            print("Telemetry failed: \(error)")
            return false
        }
    }

    private func availableCapabilities() -> [String] {
        var capabilities: [String] = ["chat"]
        if SpeechService.isSpeechRecognitionAvailable {
            capabilities.append("speech_to_text")
        }
        if SpeechService.isTextToSpeechAvailable {
            capabilities.append("text_to_speech")
        }
        return capabilities
    }
}

private struct EmptyResponse: Codable {}
