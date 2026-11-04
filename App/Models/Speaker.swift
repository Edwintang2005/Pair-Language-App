import AVFoundation

/// On-device text-to-speech. Works offline once iOS has the voice installed.
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var configuredSession = false

    func say(_ text: String, in language: Language) {
        if !configuredSession {
            // Play even when the ring/silent switch is on silent; this is the whole point of tapping the button.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            configuredSession = true
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }
}
