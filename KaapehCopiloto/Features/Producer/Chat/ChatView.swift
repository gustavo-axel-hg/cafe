//
//  ChatView.swift
//  KaapehCopiloto
//
//  Created by Cafe Swift on 28/10/25.
//

import SwiftUI

struct ChatView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: ChatViewModel
    @State private var showAccessibilityChecklist = false

    init(initialContext: String? = nil, viewModel: ChatViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ChatViewModel(initialContext: initialContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageView(message: message) {
                                viewModel.retryLastInteraction()
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal)
                }
                .background(Color(.systemBackground))
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if !viewModel.suggestedPrompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.suggestedPrompts) { suggestion in
                            Button(action: { viewModel.sendSuggestion(suggestion) }) {
                                Text(suggestion.text)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                            .accessibilityLabel("Sugerencia: \(suggestion.text)")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGray6))
            }

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: toggleRecording) {
                        Image(systemName: viewModel.isRecording ? "waveform" : "mic")
                            .font(.title2)
                            .foregroundStyle(viewModel.isRecording ? .red : (viewModel.isSpeechToTextEnabled ? .green : .gray))
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .disabled(!viewModel.isSpeechToTextEnabled)
                    .accessibilityLabel(viewModel.isRecording ? String(localized: "Detener dictado") : String(localized: "Iniciar dictado"))

                    TextField(String(localized: "Escribe tu pregunta..."), text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .accessibilityLabel(String(localized: "Campo de texto para preguntas"))

                    Button(action: viewModel.sendMessage) {
                        Image(systemName: viewModel.isSending ? "paperplane" : "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .green)
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
                    .accessibilityLabel(String(localized: "Enviar mensaje"))
                }
                .padding(.horizontal)

                if viewModel.isSending {
                    ProgressView(String(localized: "Esperando respuesta del copiloto"))
                        .progressViewStyle(.circular)
                        .padding(.bottom, 4)
                }

                if let error = viewModel.activeError {
                    HStack {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text(error.localizedDescription)
                            .font(.footnote)
                        Spacer()
                        Button(String(localized: "Reintentar")) {
                            viewModel.retryLastInteraction()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .accessibilityHint(String(localized: "Hubo un error, presiona reintentar"))
                }
            }
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .navigationTitle(String(localized: "Copiloto IA"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAccessibilityChecklist) {
            AccessibilityChecklistView(checks: viewModel.accessibilityChecks)
        }
        .onAppear { viewModel.onAppear() }
    }

    private func toggleRecording() {
        if viewModel.isRecording {
            viewModel.stopRecording()
        } else {
            viewModel.startRecording()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.backward")
            }
            .accessibilityLabel(String(localized: "Cerrar conversación"))
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Toggle(String(localized: "Dictado"), isOn: $viewModel.isSpeechToTextEnabled)
                    .onChange(of: viewModel.isSpeechToTextEnabled) { _, newValue in viewModel.handleSpeechToTextChange(to: newValue) }
                Toggle(String(localized: "Lectura en voz alta"), isOn: $viewModel.isTextToSpeechEnabled)
                    .onChange(of: viewModel.isTextToSpeechEnabled) { _, newValue in viewModel.handleTextToSpeechChange(to: newValue) }
                Button(String(localized: "Checklist de accesibilidad")) {
                    showAccessibilityChecklist = true
                }
                Button(String(localized: "Reproducir última respuesta")) {
                    viewModel.speakLastAssistantMessage()
                }
                if viewModel.isSending {
                    Button(String(localized: "Cancelar solicitud")) {
                        viewModel.cancelPendingRequest()
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }

            Button {
                viewModel.markLastAssistantMessageAsKey()
            } label: {
                Image(systemName: "bookmark")
            }
            .accessibilityLabel(String(localized: "Guardar conversación"))
        }
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    let retryAction: () -> Void

    init(message: ChatMessage, retryAction: @escaping () -> Void) {
        self.message = message
        self.retryAction = retryAction
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if message.isFromUser {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 6) {
                bubble
                metaInfo
            }
            .frame(maxWidth: 320, alignment: message.isFromUser ? .trailing : .leading)

            if !message.isFromUser {
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.isAssistantTyping {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(message.text)
                    .textSelection(.enabled)
            }

            if !message.metadata.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(message.metadata.suggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "lightbulb")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if message.isRetryable {
                Button(String(localized: "Reintentar"), action: retryAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(message.isFromUser ? Color.green : Color(.systemGray6))
        .foregroundStyle(message.isFromUser ? Color.white : Color.primary)
        .cornerRadius(18)
        .overlay(alignment: .topTrailing) {
            if message.metadata.isKeyMoment {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
    }

    @ViewBuilder
    private var metaInfo: some View {
        HStack(spacing: 8) {
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let confidence = message.metadata.confidence {
                Label(String(format: "%.0f%%", confidence * 100), systemImage: "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let source = message.metadata.source {
                Label(source, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityLabel: String {
        let speaker = message.isFromUser ? String(localized: "Tú") : String(localized: "Copiloto")
        return "\(speaker): \(message.text)"
    }
}

struct AccessibilityChecklistView: View {
    @Environment(\.dismiss) private var dismiss
    let checks: [AccessibilityCheck]

    var body: some View {
        NavigationStack {
            List(checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.status.symbolName)
                        .foregroundStyle(check.status.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.title)
                            .font(.headline)
                        Text(check.recommendation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle(String(localized: "Checklist de accesibilidad"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Cerrar"), action: dismiss.callAsFunction)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(initialContext: "Roya del café")
    }
}
