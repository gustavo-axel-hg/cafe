import AVFoundation
import Combine
import Foundation
#if canImport(Speech)
import Speech
#endif

@MainActor
final class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()

    #if canImport(Speech)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.preferredLanguages.first ?? "es-MX"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    #endif

    private let synthesizer = AVSpeechSynthesizer()

    @Published var transcribedText: String = ""
    @Published var authorizationStatus: Authorization = .notDetermined

    enum Authorization {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    static var isSpeechRecognitionAvailable: Bool {
        #if canImport(Speech)
        return SFSpeechRecognizer(locale: Locale(identifier: Locale.preferredLanguages.first ?? "es-MX")) != nil
        #else
        return false
        #endif
    }

    static var isTextToSpeechAvailable: Bool {
        AVSpeechSynthesisVoice.speechVoices().isEmpty == false
    }

    private override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = true
    }

    func requestAuthorization() {
        #if canImport(Speech)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            Task { @MainActor in
                switch status {
                case .authorized:
                    self.authorizationStatus = .authorized
                case .denied:
                    self.authorizationStatus = .denied
                case .restricted:
                    self.authorizationStatus = .restricted
                case .notDetermined:
                    self.authorizationStatus = .notDetermined
                @unknown default:
                    self.authorizationStatus = .restricted
                }
            }
        }
        #else
        authorizationStatus = .denied
        #endif
    }

    func startRecording(onTranscription: @escaping (String) -> Void) throws {
        #if canImport(Speech)
        guard authorizationStatus == .authorized else {
            throw NSError(domain: "SpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permiso de voz no concedido"])
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    let transcript = result.bestTranscription.formattedString
                    self.transcribedText = transcript
                    onTranscription(transcript)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                self.stopRecording()
            }
        }
        #else
        throw NSError(domain: "SpeechService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech framework no disponible"])
        #endif
    }

    func stopRecording() {
        #if canImport(Speech)
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    func speak(_ text: String, language: String = Locale.preferredLanguages.first ?? "es-MX") {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
