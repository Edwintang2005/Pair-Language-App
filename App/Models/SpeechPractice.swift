import AVFoundation
import Foundation
import Observation
import Speech

/// One sentence to copy in the speaking drill.
struct SpeakingItem: Identifiable, Hashable {
    let id = UUID()
    let word: Word
    let example: Example
    /// The sentence's words, for showing which ones the speech check caught.
    let words: [SentenceTile]

    static func items<G: RandomNumberGenerator>(wordIDs: [String], content: ContentLibrary, limit: Int = 10,
                                               using rng: inout G) -> [SpeakingItem] {
        var items: [SpeakingItem] = []
        for word in wordIDs.compactMap({ content.words[$0] }).shuffled(using: &rng) where items.count < limit {
            if let item = item(for: word, content: content) { items.append(item) }
        }
        return items
    }

    static func items(wordIDs: [String], content: ContentLibrary, limit: Int = 10) -> [SpeakingItem] {
        var rng = SystemRandomNumberGenerator()
        return items(wordIDs: wordIDs, content: content, limit: limit, using: &rng)
    }

    static func item(for word: Word, content: ContentLibrary) -> SpeakingItem? {
        guard let example = word.examples.first,
              let words = SentenceBuilder.words(of: example, language: word.language, content: content),
              !words.isEmpty else { return nil }
        return SpeakingItem(word: word, example: example, words: words)
    }

    static func eligibleCount(in wordIDs: [String], content: ContentLibrary) -> Int {
        wordIDs.filter { id in content.words[id].flatMap { item(for: $0, content: content) } != nil }.count
    }
}

/// Records you, and plays you back. One recording at a time, kept in a temporary file that's
/// deleted when you record again or move on.
@Observable
final class VoiceRecorder {
    enum State: Equatable {
        case idle
        case recording
        case recorded(URL)
    }

    /// The longest a recording runs before it stops by itself.
    static let maxSeconds: Double = 15

    private(set) var state: State = .idle
    /// True while the original or your recording is playing.
    private(set) var isPlaying = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var autoStop: Task<Void, Never>?

    var recording: URL? {
        if case .recorded(let url) = state { return url }
        return nil
    }

    static var hasPermission: Bool { AVAudioApplication.shared.recordPermission == .granted }
    static var wasDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }

    /// Asks for the microphone the first time; returns whether Pair may record.
    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() {
        discard()
        Speaker.shared.stop()
        AudioSession.useRecording()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings), recorder.record() else { return }
        self.recorder = recorder
        state = .recording
        autoStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxSeconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        autoStop?.cancel()
        guard let recorder, state == .recording else { return }
        recorder.stop()
        self.recorder = nil
        state = .recorded(recorder.url)
    }

    /// Plays your recording and returns when it's done.
    func playRecording() async {
        guard let url = recording, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        Speaker.shared.stop()
        self.player?.stop()
        self.player = player
        isPlaying = true
        player.play()
        // AVAudioPlayer's delegate would need its own object; its duration is enough to wait on.
        try? await Task.sleep(for: .seconds(player.duration + 0.1))
        if self.player === player { isPlaying = false }
    }

    /// The original, then you, straight after: the comparison the drill is built around.
    func compare(with text: String, in language: Language) async {
        stopPlaying()
        isPlaying = true
        await Speaker.shared.speak(text, in: language)
        guard isPlaying else { return }  // something else took over in the meantime
        try? await Task.sleep(for: .seconds(0.3))
        await playRecording()
        isPlaying = false
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        Speaker.shared.stop()
        isPlaying = false
    }

    /// Stops everything and deletes the recording.
    func discard() {
        autoStop?.cancel()
        recorder?.stop()
        recorder = nil
        stopPlaying()
        if let url = recording { try? FileManager.default.removeItem(at: url) }
        state = .idle
    }
}

/// "Which words did it understand?": on-device speech recognition over your recording.
/// Never runs unless the iPhone can do it offline, so nothing ever leaves the phone.
nonisolated enum SpeechCheck {
    enum Outcome: Equatable {
        /// What the recogniser heard.
        case heard(String)
        /// It ran but caught nothing.
        case nothing
        /// It can't run yet; `Availability` says why and what to do about it.
        case unavailable(Availability)
    }

    /// Whether the check can run, and if not, why.
    enum Availability: Equatable {
        case ready
        /// Speech recognition is turned off for Pair (or restricted by Screen Time).
        case needsPermission
        /// The iPhone hasn't got this language for offline recognition yet. Adding the language's
        /// keyboard with Dictation on downloads it; some older iPhones can't do it at all.
        case needsDownload
        /// iOS doesn't recognise this language at all.
        case unsupported
        /// Recognition is briefly unavailable (e.g. still setting up); trying again usually works.
        case busy
    }

    /// `locale` is the language's speech code, e.g. "zh-CN". Doesn't ask for anything: permission
    /// that hasn't been asked for yet counts as ready, since the check asks the first time.
    static func availability(locale: String) -> Availability {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else { return .unsupported }
        guard recognizer.supportsOnDeviceRecognition else { return .needsDownload }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: return .needsPermission
        default: break
        }
        return recognizer.isAvailable ? .ready : .busy
    }

    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            // The handler runs on a background queue: resuming a continuation is fine there.
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    /// `locale` is the language's speech code, e.g. "zh-CN".
    static func check(_ url: URL, locale: String) async -> Outcome {
        // Only ask for permission when it can actually be used: offline recognition for this language.
        let availability = availability(locale: locale)
        guard availability == .ready else { return .unavailable(availability) }
        guard await authorize() else { return .unavailable(.needsPermission) }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            return .unavailable(.unsupported)
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = false

        let once = Once()
        let text: String? = await withCheckedContinuation { continuation in
            once.task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if error != nil {
                    // Includes "no speech detected".
                    once.run { continuation.resume(returning: nil) }
                }
            }
        }
        withExtendedLifetime(recognizer) {}
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .nothing }
        return .heard(text)
    }

    /// Makes sure the continuation is resumed exactly once, and keeps the task alive meanwhile.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        var task: SFSpeechRecognitionTask?

        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
            task = nil
        }
    }
}

/// Lines a transcript up against the sentence's words.
nonisolated enum SpeechMatch {
    /// For each word of the sentence, whether the transcript contains it.
    static func heard(_ words: [String], in transcript: String, language: Language) -> [Bool] {
        switch language {
        case .german:
            let said = Set(transcript.split(whereSeparator: { $0.isWhitespace }).map(normalisedGerman))
            return words.map { said.contains(normalisedGerman($0)) }
        case .chinese:
            let said = normalisedChinese(transcript)
            return words.map { said.contains(normalisedChinese($0)) }
        }
    }

    private static func normalisedGerman(_ word: some StringProtocol) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Recognisers can't tell 他/她/它 or 的/得/地 apart by sound, and write numbers as digits,
    /// so those count as the same.
    private static func normalisedChinese(_ text: String) -> String {
        let same: [Character: Character] = [
            "她": "他", "它": "他", "得": "的", "地": "的", "两": "二",
            "0": "零", "1": "一", "2": "二", "3": "三", "4": "四", "5": "五", "6": "六", "7": "七", "8": "八", "9": "九",
        ]
        return String(text.compactMap { character -> Character? in
            guard character.isLetter || character.isNumber else { return nil }
            return same[character] ?? character
        })
    }
}
