//
//  SwiftDataService.swift
//  KaapehCopiloto
//
//  Created by Cafe Swift on 28/10/25.
//

import Foundation
import SwiftData

@MainActor
class SwiftDataService {
    static let shared = SwiftDataService()
    
    var modelContainer: ModelContainer?
    var modelContext: ModelContext?
    
    private init() {
        setupModelContainer()
    }
    
    func setupModelContainer() {
        let schema = Schema([
            UserProfile.self,
            AccessibilityConfig.self,
            DiagnosisRecord.self,
            ActionItem.self,
            ChatConversation.self,
            ChatTurnRecord.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    // User profil operations
    func createUserProfile(userName: String, role: String, preferredLanguage: String) throws -> UserProfile {
        guard let context = modelContext else {
            throw NSError(domain: "SwiftDataService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ModelContext not available"])
        }
        
        let newUser = UserProfile(userName: userName, role: role, preferredLanguage: preferredLanguage)
        context.insert(newUser)
        
        try context.save()
        return newUser
    }
    
    func fetchCurrentUser() -> UserProfile? {
        guard let context = modelContext else {return nil }
        
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        
        do {
            let users = try context.fetch(descriptor)
            return users.first
        } catch {
            print("Error fetching user: \(error)")
            return nil
        }
    }
    
    // diafnosis operations
    func saveDiagnosis(detectedIssue: String, confidence: Double, imagePath: String?, user: UserProfile) throws -> DiagnosisRecord {
        guard let context = modelContext else{
            throw NSError(domain: "SwiftDataService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ModelContext not available"])
        }
        
        let diagnosis = DiagnosisRecord(detectedIssue: detectedIssue, confidence: confidence, imagePath: imagePath)
        diagnosis.userProfile = user
        
        context.insert(diagnosis)
        try context.save()
        
        return diagnosis
    }
    
    func fetchDiagnosisHistory(for user: UserProfile) -> [DiagnosisRecord] {
        guard let context = modelContext else {return[] }
        
        let descriptor = FetchDescriptor<DiagnosisRecord> (
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let allDiagnoses = try context.fetch(descriptor)
            // Filtrar manualmente por usuario
            return allDiagnoses.filter { $0.userProfile?.userID == user.userID }
        } catch {
            print("Error fetching diagnosis history: \(error)")
            return []
        }
    }
    
    // accessibility config
    func updateAccessibilitySettings(for user: UserProfile, config: AccessibilityConfig) throws {
        guard let context = modelContext else {
            throw NSError(domain: "SwiftDataService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ModelContext not available"])
        }

        user.accessibilitySettings = config
        config.userProfile = user

        try context.save()
    }

    // MARK: - Chat logging

    func saveKeyConversation(conversationId: UUID, topic: String?, entries: [ChatTranscriptEntry]) throws {
        guard let context = modelContext else {
            throw NSError(domain: "SwiftDataService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ModelContext not available"])
        }

        let descriptor = FetchDescriptor<ChatConversation>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        let conversation: ChatConversation
        if let existing = try context.fetch(descriptor).first {
            conversation = existing
        } else {
            conversation = ChatConversation(conversationId: conversationId, topic: topic ?? "Conversación Copiloto")
            context.insert(conversation)
        }

        conversation.topic = topic ?? conversation.topic
        conversation.lastUpdatedAt = Date()

        // remove stale turns to avoid duplicates
        for turn in conversation.turns {
            context.delete(turn)
        }
        conversation.turns.removeAll()

        for entry in entries {
            let turn = ChatTurnRecord(role: entry.role, text: entry.text, timestamp: entry.timestamp, isKeyMoment: entry.isKeyMoment)
            turn.conversation = conversation
            conversation.turns.append(turn)
        }

        try context.save()
    }

    func fetchKeyConversations(limit: Int = 10) throws -> [ChatConversation] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<ChatConversation>(
            sortBy: [SortDescriptor(\.lastUpdatedAt, order: .reverse)],
            fetchLimit: limit
        )

        return try context.fetch(descriptor)
    }
}

struct ChatTranscriptEntry {
    let role: String
    let text: String
    let timestamp: Date
    let isKeyMoment: Bool
}
