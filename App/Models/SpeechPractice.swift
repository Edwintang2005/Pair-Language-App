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
    /// Bumped whenever playback starts or stops, so a playback that's been superseded can't
    /// change `isPlaying` when it finishes.
    private var generation = 0

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
            .appendingPathComponent("\(Self.filePrefix)\(UUID().uuidString).m4a")
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
        stopPlaying()
        let current = generation
        await play(current)
        if generation == current { isPlaying = false }
    }

    /// The original, then you, straight after: the comparison the drill is built around.
    func compare(with text: String, in language: Language) async {
        stopPlaying()
        let current = generation
        isPlaying = true
        await Speaker.shared.speak(text, in: language)
        guard generation == current else { return }  // something else took over in the meantime
        try? await Task.sleep(for: .seconds(0.3))
        guard generation == current else { return }
        await play(current)
        if generation == current { isPlaying = false }
    }

    private func play(_ current: Int) async {
        guard let url = recording, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        isPlaying = true
        player.play()
        // AVAudioPlayer's delegate would need its own object; its duration is enough to wait on.
        try? await Task.sleep(for: .seconds(player.duration + 0.1))
        if generation == current { self.player = nil }
    }

    func stopPlaying() {
        generation += 1
        player?.stop()
        player = nil
        Speaker.shared.stop()
        isPlaying = false
    }

    /// Stops everything and deletes the recording.
    func discard() {
        autoStop?.cancel()
        // Still recording: the file is the recorder's, not yet in `state`.
        let inProgress = recorder?.url
        recorder?.stop()
        recorder = nil
        stopPlaying()
        for url in [inProgress, recording].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
    }

    /// Deletes any recording left over from a run that ended abruptly (the app was killed mid-drill).
    static func removeLeftoverRecordings() {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(filePrefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static let filePrefix = "pair-recording-"
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
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if error != nil {
                    // Includes "no speech detected".
                    once.run { continuation.resume(returning: nil) }
                }
            }
            once.hold(task)
            // A recording is at most 15 seconds; never leave the spinner up if recognition stalls.
            Task.detached {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                once.run { continuation.resume(returning: nil) }
            }
        }
        withExtendedLifetime(recognizer) {}
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .nothing }
        return .heard(text)
    }

    /// Makes sure the continuation is resumed exactly once, and keeps the task alive meanwhile.
    static let timeoutSeconds: Double = 20

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var task: SFSpeechRecognitionTask?

        /// Keeps the task alive until it finishes; cancels it straight away if it already has.
        func hold(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            defer { lock.unlock() }
            if done { task.cancel() } else { self.task = task }
        }

        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
            task?.cancel()
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
            // Recognisers often write numbers as digits: "zwei" and "2" both become "2".
            return words.map { said.contains(normalisedGerman($0)) }
        case .chinese:
            let said = normalisedChinese(transcript)
            return words.map { said.contains(normalisedChinese($0)) }
        }
    }

    private static func normalisedGerman(_ word: some StringProtocol) -> String {
        let plain = word.lowercased().filter { $0.isLetter || $0.isNumber }
        return germanNumbers[plain] ?? plain
    }

    /// Number words as digits. "ein/eine" are left alone: they're usually "a", not "one".
    private static let germanNumbers: [String: String] = [
        "null": "0", "eins": "1", "zwei": "2", "drei": "3", "vier": "4", "fünf": "5", "sechs": "6",
        "sieben": "7", "acht": "8", "neun": "9", "zehn": "10", "elf": "11", "zwölf": "12",
        "zwanzig": "20", "dreißig": "30", "hundert": "100", "tausend": "1000",
    ]

    /// 2 → 二, 10 → 十, 25 → 二十五, 100 → 一百, 105 → 一百零五, 3000 → 三千 (up to 9999).
    static func chineseNumeral(_ n: Int) -> String? {
        guard (0...9999).contains(n) else { return nil }
        let digits = Array("零一二三四五六七八九")
        if n < 10 { return String(digits[n]) }
        if n < 20 { return "十" + (n == 10 ? "" : String(digits[n % 10])) }
        let units: [(Int, Character)] = [(1000, "千"), (100, "百"), (10, "十")]
        var result = ""
        var rest = n
        var pendingZero = false
        for (size, name) in units {
            let d = rest / size
            rest %= size
            if d > 0 {
                if pendingZero { result.append("零"); pendingZero = false }
                result.append(digits[d]); result.append(name)
            } else if !result.isEmpty {
                pendingZero = true
            }
        }
        if rest > 0 {
            if pendingZero { result.append("零") }
            result.append(digits[rest])
        }
        return result
    }

    /// Recognisers can't tell 他/她/它 or 的/得/地 apart by sound, and write numbers as digits,
    /// so those count as the same.
    private static func normalisedChinese(_ text: String) -> String {
        let same: [Character: Character] = ["她": "他", "它": "他", "得": "的", "地": "的", "两": "二"]
        // Digit runs become numerals first: "10" is 十, not 一零.
        var spelled = ""
        var run = ""
        for character in text + " " {
            if character.isASCII && character.isNumber {
                run.append(character)
                continue
            }
            if !run.isEmpty {
                spelled += Int(run).flatMap(chineseNumeral) ?? run
                run = ""
            }
            spelled.append(character)
        }
        return String(spelled.compactMap { character -> Character? in
            guard character.isLetter || character.isNumber else { return nil }
            return same[character] ?? character
        })
    }
}
