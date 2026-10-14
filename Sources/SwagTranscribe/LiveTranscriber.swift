import AVFoundation
import Speech

/// Live microphone transcription with Apple's on-device Speech framework.
/// Whisper is batch-only; SFSpeechRecognizer streams natively. SpeechAnalyzer (macOS 26+) is the upgrade if quality matters.
@MainActor final class LiveTranscriber: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var text = ""
    @Published private(set) var error: String?

    private static let locales = ["nl": "nl-NL", "en": "en-US", "de": "de-DE", "fr": "fr-FR", "es": "es-ES"]

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var committed = ""
    /// Written on the main actor, read by the audio tap on the realtime audio thread. Appending to a request that
    /// was just replaced only drops that one buffer, so no lock.
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?

    func toggle(language: String) {
        if running { stop() } else { start(language) }
    }

    private func start(_ language: String) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.error = localized(
                        "No permission for speech recognition (System Settings → Privacy & Security)",
                        "Geen toestemming voor spraakherkenning (Systeeminstellingen → Privacy en beveiliging)")
                    return
                }
                self.begin(language)
            }
        }
    }

    private func begin(_ language: String) {
        let locale = Locale(identifier: Self.locales[language] ?? Locale.current.identifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            error = localized(
                "No speech recognition available for \(language)", "Geen spraakherkenning beschikbaar voor \(language)")
            return
        }
        self.recognizer = recognizer
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 2048, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            self.error = error.localizedDescription
            input.removeTap(onBus: 0)
            return
        }
        text = ""
        committed = ""
        error = nil
        running = true
        newRequest()
    }

    /// One request per utterance: when the recognizer finalizes, commit the text and open the next request.
    private func newRequest() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.running else { return }
                if let result {
                    self.text = self.committed + result.bestTranscription.formattedString
                    if result.isFinal {
                        self.committed = self.text + "\n"
                        self.newRequest()
                    }
                } else if let error {
                    self.error = error.localizedDescription
                    self.stop()
                }
            }
        }
    }

    func stop() {
        running = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}
