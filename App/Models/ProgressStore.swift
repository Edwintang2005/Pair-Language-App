import Foundation
import Observation

/// Everything this phone remembers. Stored as one small JSON file; nothing leaves the device.
struct ProgressData: Codable, Equatable {
    /// The language this phone's owner is learning. `nil` until onboarding is done.
    var learning: Language?
    /// The session you're both on. Advances when "Finish session" is tapped.
    var currentSession: Int = 1
    /// Words in the current session the learner has marked as taught.
    var taught: Set<String> = []
    /// Review schedule for every learned word, keyed by word ID.
    var reviews: [String: ReviewState] = [:]
    /// When each session was finished, keyed by session number.
    var completed: [Int: Date] = [:]
    /// `nil` until reminders have been set up.
    var reminders: ReminderSettings?
    /// The "turn on reminders" card on Today was dismissed.
    var reminderPromptDismissed = false
    /// The word shown on the Lock Screen widget. `nil` rotates through learned words.
    var pinnedWordID: String?

    init() {}

    // Decode leniently, so adding a field in a later version never wipes a year of progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        learning = try c.decodeIfPresent(Language.self, forKey: .learning)
        currentSession = try c.decodeIfPresent(Int.self, forKey: .currentSession) ?? 1
        taught = try c.decodeIfPresent(Set<String>.self, forKey: .taught) ?? []
        reviews = try c.decodeIfPresent([String: ReviewState].self, forKey: .reviews) ?? [:]
        completed = try c.decodeIfPresent([Int: Date].self, forKey: .completed) ?? [:]
        reminders = try c.decodeIfPresent(ReminderSettings.self, forKey: .reminders)
        reminderPromptDismissed = try c.decodeIfPresent(Bool.self, forKey: .reminderPromptDismissed) ?? false
        pinnedWordID = try c.decodeIfPresent(String.self, forKey: .pinnedWordID)
    }
}

@Observable
final class ProgressStore {
    private(set) var data: ProgressData
    @ObservationIgnored private let fileURL: URL?

    /// - Parameter fileURL: where to persist. `nil` keeps everything in memory (previews, tests).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL,
           let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ProgressData.self, from: raw) {
            data = decoded
        } else {
            data = ProgressData()
        }
    }

    static func live() -> ProgressStore {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProgressStore(fileURL: dir.appending(path: "progress.json"))
    }

    // MARK: Reading

    var learning: Language? { data.learning }
    var teaching: Language? { data.learning?.other }
    var currentSession: Int { data.currentSession }
    var completedCount: Int { data.completed.count }
    var learnedCount: Int { data.reviews.count }

    func isTaught(_ wordID: String) -> Bool { data.taught.contains(wordID) }
    func isLearned(_ wordID: String) -> Bool { data.reviews[wordID] != nil }
    func review(for wordID: String) -> ReviewState? { data.reviews[wordID] }

    func canFinish(_ session: Session) -> Bool {
        guard let learning else { return false }
        return session.wordIDs(for: learning).allSatisfy(isTaught)
    }

    func dueWordIDs(now: Date = .now) -> [String] {
        data.reviews
            .filter { $0.value.due <= now }
            .sorted { ($0.value.due, $0.key) < ($1.value.due, $1.key) }
            .map(\.key)
    }

    var learnedWordIDs: [String] { Array(data.reviews.keys) }

    var nextDueDate: Date? { data.reviews.values.map(\.due).min() }

    func strongCount() -> Int {
        data.reviews.values.filter { Scheduler.strength(of: $0) == .strong }.count
    }

    /// Consecutive days, ending today or yesterday, on which at least one session was finished.
    func streak(now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(data.completed.values.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: Changing

    func choose(learning language: Language) {
        update { $0.learning = language }
    }

    func toggleTaught(_ wordID: String) {
        update {
            if $0.taught.contains(wordID) { $0.taught.remove(wordID) } else { $0.taught.insert(wordID) }
        }
    }

    /// Adds the session's words to review and moves both of you on to the next session.
    func finish(_ session: Session, now: Date = .now, calendar: Calendar = .current) {
        guard let learning, canFinish(session) else { return }
        update { data in
            for id in session.wordIDs(for: learning) where data.reviews[id] == nil {
                data.reviews[id] = Scheduler.newCard(learnedOn: now, calendar: calendar)
            }
            data.completed[session.number] = now
            data.currentSession = session.number + 1
            data.taught = []
        }
    }

    func record(_ grade: ReviewGrade, for wordID: String, now: Date = .now, calendar: Calendar = .current) {
        guard let state = data.reviews[wordID] else { return }
        update { $0.reviews[wordID] = Scheduler.review(state, grade: grade, now: now, calendar: calendar) }
    }

    /// For getting back in step with your partner. Keeps review history.
    func setCurrentSession(_ number: Int) {
        guard number != data.currentSession else { return }
        update {
            $0.currentSession = max(1, number)
            $0.taught = []
        }
    }

    // MARK: Reminders

    var reminders: ReminderSettings? { data.reminders }

    /// Offer reminders once you've finished a session, until they're set up or dismissed.
    var showsReminderPrompt: Bool {
        data.reminders == nil && !data.reminderPromptDismissed && !data.completed.isEmpty
    }

    func setReminders(_ settings: ReminderSettings) {
        update { $0.reminders = settings }
    }

    func dismissReminderPrompt() {
        update { $0.reminderPromptDismissed = true }
    }

    // MARK: Lock Screen widget

    /// Shows this word on the widget, or clears the pin when it's already pinned.
    func togglePin(_ wordID: String) {
        update { $0.pinnedWordID = $0.pinnedWordID == wordID ? nil : wordID }
    }

    /// What the widget rotates through when nothing is pinned.
    var widgetPoolIDs: [String] { knownWordIDs }

    /// Your own words that you've been taught or are reviewing. The drills use these.
    var knownWordIDs: [String] {
        guard let learning else { return [] }
        let prefix = learning.rawValue + "-"
        return Set(data.reviews.keys).union(data.taught)
            .filter { $0.hasPrefix(prefix) }
            .sorted()
    }

    /// Words of your partner's from sessions you've both finished, for quizzing them.
    func partnerWordIDs(in content: ContentLibrary) -> [String] {
        guard let teaching else { return [] }
        return content.sessions
            .filter { $0.number < data.currentSession }
            .flatMap { $0.wordIDs(for: teaching) }
    }

    func resetAll() {
        update { $0 = ProgressData() }
    }

    private func update(_ change: (inout ProgressData) -> Void) {
        change(&data)
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch {
            print("Pair: failed to save progress: \(error)")
        }
    }
}
