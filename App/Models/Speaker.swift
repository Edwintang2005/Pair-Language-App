import AVFoundation

/// On-device text-to-speech. Works offline once iOS has the voice installed.
final class Speaker: NSObject {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    /// Waiting for the current utterance to finish (see `speak`).
    private var finished: CheckedContinuation<Void, Never>?
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Starts speaking, cutting off anything already playing.
    func say(_ text: String, in language: Language, slow: Bool = false) {
        AudioSession.preparePlayback()
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        // Slow is for hearing tones and sounds clearly; normal is already a little under full speed.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.55 : 0.85)
        current = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    /// Speaks and returns once it's finished (or been cut off).
    func speak(_ text: String, in language: Language, slow: Bool = false) async {
        say(text, in: language, slow: slow)
        await withCheckedContinuation { continuation in
            finished = continuation
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        finished?.resume()
        finished = nil
    }

    /// A cut-off utterance reports in after the next one has started, so only the current one counts.
    fileprivate func utteranceEnded(_ id: ObjectIdentifier) {
        if id == current { finish() }
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }
}

/// The app's audio set-up: playback normally, play-and-record while the speaking drill is open.
enum AudioSession {
    /// Play even when the ring/silent switch is on silent: tapping a speaker button means "play".
    /// Leaves a recording set-up alone, since that plays through the speaker too.
    static func preparePlayback() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback && session.category != .playAndRecord else { return }
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
    }

    static func useRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    static func usePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
    }
}
