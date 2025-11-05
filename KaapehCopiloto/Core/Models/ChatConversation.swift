import Foundation
import SwiftData

/// Registro persistente de conversaciones relevantes con el copiloto.
@Model
final class ChatConversation {
    var conversationId: UUID
    var createdAt: Date
    var topic: String
    var source: String
    var lastUpdatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatTurnRecord.conversation)
    var turns: [ChatTurnRecord]

    init(conversationId: UUID, topic: String, source: String = "copiloto", createdAt: Date = Date()) {
        self.conversationId = conversationId
        self.createdAt = createdAt
        self.topic = topic
        self.source = source
        self.lastUpdatedAt = createdAt
        self.turns = []
    }
}

/// Registro de cada turno dentro de una conversación guardada.
@Model
final class ChatTurnRecord {
    var turnId: UUID
    var role: String
    var text: String
    var timestamp: Date
    var isKeyMoment: Bool

    var conversation: ChatConversation?

    init(turnId: UUID = UUID(), role: String, text: String, timestamp: Date, isKeyMoment: Bool = false) {
        self.turnId = turnId
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isKeyMoment = isKeyMoment
    }
}
