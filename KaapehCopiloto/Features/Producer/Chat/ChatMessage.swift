import Foundation

enum ChatMessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum ChatMessageStatus: String, Codable {
    case sent
    case sending
    case typing
    case failed
}

struct ChatMessageMetadata: Codable, Equatable {
    var confidence: Double?
    var source: String?
    var isKeyMoment: Bool
    var suggestions: [String]

    init(confidence: Double? = nil, source: String? = nil, isKeyMoment: Bool = false, suggestions: [String] = []) {
        self.confidence = confidence
        self.source = source
        self.isKeyMoment = isKeyMoment
        self.suggestions = suggestions
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    var role: ChatMessageRole
    var text: String
    var status: ChatMessageStatus
    var timestamp: Date
    var metadata: ChatMessageMetadata

    init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        text: String,
        status: ChatMessageStatus = .sent,
        timestamp: Date = Date(),
        metadata: ChatMessageMetadata = ChatMessageMetadata()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
        self.timestamp = timestamp
        self.metadata = metadata
    }

    var isFromUser: Bool {
        role == .user
    }

    var isAssistantTyping: Bool {
        role == .assistant && status == .typing
    }

    var isRetryable: Bool {
        status == .failed
    }
}

struct ChatSuggestion: Identifiable, Equatable {
    let id = UUID()
    let text: String
}
