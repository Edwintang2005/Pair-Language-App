import Foundation
import Testing
@testable import Pair

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ d: Int, hour: Int = 10) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
}

@MainActor
struct ContentTests {
    @Test func bundledContentLoadsAndEverySessionHasFivePerSide() throws {
        let content = try ContentLibrary.loadBundled()
        #expect(content.sessionCount >= 70)
        for session in content.sessions {
            #expect(content.words(in: session, language: .german).count == 5, "session \(session.number) de")
            #expect(content.words(in: session, language: .chinese).count == 5, "session \(session.number) zh")
        }
    }

    @Test func germanNounsShowTheirArticle() throws {
        let content = try ContentLibrary.loadBundled()
        #expect(content.words["de-haus"]?.headword == "das Haus")
        #expect(content.words["de-tuer"]?.headword == "die Tür")
        #expect(content.words["de-hallo"]?.headword == "Hallo")
        #expect(content.words["de-gehen"]?.grammarLine == "er geht · ist gegangen")
    }

    @Test func everyWordAppearsInItsExample() throws {
        let content = try ContentLibrary.loadBundled()
        for word in content.words.values {
            let used = word.examples.contains { example in
                switch word.language {
                case .chinese:
                    return example.text.contains(word.word)
                case .german:
                    // Whole words or phrases only, ignoring case: "Haus" in "Das Haus ist groß.",
                    // "gute Nacht" in "Gute Nacht, schlaf gut!", but not "Haus" in "Hausaufgaben".
                    let text = example.text.lowercased()
                    let target = word.word.lowercased()
                    var searchStart = text.startIndex
                    while let range = text.range(of: target, range: searchStart..<text.endIndex) {
                        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
                        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
                        if !(before?.isLetter ?? false) && !(after?.isLetter ?? false) { return true }
                        searchStart = range.upperBound
                    }
                    return false
                }
            }
            #expect(used, "\(word.id): '\(word.word)' isn't in its example")
        }
    }

    @Test func seinIsTaughtAsIst() throws {
        let content = try ContentLibrary.loadBundled()
        let ist = try #require(content.words["de-sein"])
        #expect(ist.headword == "ist")
        #expect(ist.examples.first?.text == "Das ist gut.")
    }

    @Test func searchMatchesPinyinAndMeaning() throws {
        let content = try ContentLibrary.loadBundled()
        let room = try #require(content.words["zh-fang-jian"])
        #expect(room.matches("fangjian"))
        #expect(room.matches("room"))
        #expect(!room.matches("coffee"))
    }
}

@MainActor
struct SchedulerTests {
    @Test func newWordIsDueTomorrowMorning() {
        let state = Scheduler.newCard(learnedOn: day(4, hour: 21), calendar: calendar)
        #expect(state.box == 1)
        #expect(state.due == day(5, hour: 0))
    }

    @Test func gradesMoveBoxes() {
        let start = ReviewState(box: 3, due: day(4, hour: 0))
        #expect(Scheduler.review(start, grade: .again, now: day(4), calendar: calendar).box == 1)
        let good = Scheduler.review(start, grade: .good, now: day(4), calendar: calendar)
        #expect(good.box == 4)
        #expect(good.due == day(12, hour: 0)) // box 4 = 8 days
        #expect(good.reviewCount == 1)
        #expect(Scheduler.review(start, grade: .easy, now: day(4), calendar: calendar).box == 5)
    }

    @Test func boxIsCappedAtTheTop() {
        let top = ReviewState(box: Scheduler.maxBox, due: day(4, hour: 0))
        #expect(Scheduler.review(top, grade: .easy, now: day(4), calendar: calendar).box == Scheduler.maxBox)
    }
}

@MainActor
struct ProgressStoreTests {
    private func session(_ content: ContentLibrary, _ n: Int) throws -> Session {
        try #require(content.session(n))
    }

    @Test func cannotFinishUntilAllFiveAreTaught() throws {
        let content = try ContentLibrary.loadBundled()
        let store = ProgressStore(fileURL: nil)
        store.choose(learning: .german)
        let s1 = try session(content, 1)

        for id in s1.de.dropLast() { store.toggleTaught(id) }
        #expect(!store.canFinish(s1))
        store.finish(s1, now: day(4), calendar: calendar)
        #expect(store.currentSession == 1)

        // Teaching words don't count towards finishing.
        for id in s1.zh { store.toggleTaught(id) }
        #expect(!store.canFinish(s1))

        store.toggleTaught(s1.de.last!)
        #expect(store.canFinish(s1))
    }

    @Test func finishingAddsWordsToReviewAndAdvances() throws {
        let content = try ContentLibrary.loadBundled()
        let store = ProgressStore(fileURL: nil)
        store.choose(learning: .chinese)
        let s1 = try session(content, 1)
        for id in s1.zh { store.toggleTaught(id) }

        store.finish(s1, now: day(4), calendar: calendar)

        #expect(store.currentSession == 2)
        #expect(store.learnedCount == 5)
        #expect(Set(store.learnedWordIDs) == Set(s1.zh))
        #expect(!store.isTaught(s1.zh[0]))
        #expect(store.dueWordIDs(now: day(4, hour: 23)).isEmpty)
        #expect(store.dueWordIDs(now: day(5, hour: 1)).count == 5)
    }

    @Test func progressSurvivesARelaunch() throws {
        let content = try ContentLibrary.loadBundled()
        let url = FileManager.default.temporaryDirectory.appending(path: "pair-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ProgressStore(fileURL: url)
        store.choose(learning: .german)
        let s1 = try session(content, 1)
        for id in s1.de { store.toggleTaught(id) }
        store.finish(s1, now: day(4), calendar: calendar)

        let reopened = ProgressStore(fileURL: url)
        #expect(reopened.data == store.data)
        #expect(reopened.learning == .german)
        #expect(reopened.currentSession == 2)
    }

    @Test func oldFilesWithMissingFieldsStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pair-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"learning":"de","currentSession":7}"#.utf8).write(to: url)

        let store = ProgressStore(fileURL: url)
        #expect(store.learning == .german)
        #expect(store.currentSession == 7)
        #expect(store.learnedCount == 0)
    }

    @Test func strengthCountsAndNextReview() throws {
        var data = ProgressData()
        data.learning = .german
        data.reviews = [
            "a": ReviewState(box: 1, due: day(4, hour: 0)),
            "b": ReviewState(box: 3, due: day(6, hour: 0)),
            "c": ReviewState(box: 4, due: day(6, hour: 0)),
            "d": ReviewState(box: 6, due: day(9, hour: 0)),
        ]
        let url = FileManager.default.temporaryDirectory.appending(path: "pair-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(data).write(to: url)
        let store = ProgressStore(fileURL: url)

        #expect(store.strengthCounts() == [.new: 1, .learning: 2, .strong: 1])
        let next = try #require(store.upcomingReview(after: day(4, hour: 12), calendar: calendar))
        #expect(next.date == day(6, hour: 0))
        #expect(next.count == 2)
        #expect(store.upcomingReview(after: day(10), calendar: calendar) == nil)
    }

    @Test func streakCountsConsecutiveDays() throws {
        let content = try ContentLibrary.loadBundled()
        let store = ProgressStore(fileURL: nil)
        store.choose(learning: .german)
        for (n, d) in [(1, 1), (2, 2), (3, 3)] {
            let s = try session(content, n)
            for id in s.de { store.toggleTaught(id) }
            store.finish(s, now: day(d), calendar: calendar)
        }
        #expect(store.streak(now: day(3), calendar: calendar) == 3)
        #expect(store.streak(now: day(4), calendar: calendar) == 3) // yesterday still counts
        #expect(store.streak(now: day(5), calendar: calendar) == 0)
    }
}

@MainActor
struct ReminderPlannerTests {
    private let sessions = [
        Session(number: 1, theme: "Greetings", conversationStarter: "", de: [], zh: []),
        Session(number: 2, theme: "Me, you & us", conversationStarter: "", de: [], zh: []),
    ]

    private func data(reminders: ReminderSettings? = ReminderSettings(), session: Int = 2,
                      dueOn days: [Int] = [], completedOn: Int? = nil) -> ProgressData {
        var d = ProgressData()
        d.learning = .german
        d.currentSession = session
        d.reminders = reminders
        for (i, dueDay) in days.enumerated() {
            d.reviews["w\(i)"] = ReviewState(box: 1, due: day(dueDay, hour: 0))
        }
        if let completedOn { d.completed[1] = day(completedOn, hour: 9) }
        return d
    }

    @Test func nothingWhenRemindersAreOffOrNeverSetUp() {
        #expect(ReminderPlanner.plan(data: data(reminders: nil), sessions: sessions, now: day(4), calendar: calendar).isEmpty)
        var off = ReminderSettings()
        off.enabled = false
        #expect(ReminderPlanner.plan(data: data(reminders: off), sessions: sessions, now: day(4), calendar: calendar).isEmpty)
    }

    @Test func dueWordsGiveAReviewReminderTonight() throws {
        let plan = ReminderPlanner.plan(data: data(dueOn: [4, 4, 4]), sessions: sessions, now: day(4), calendar: calendar)
        let first = try #require(plan.first)
        #expect(first.date == day(4, hour: 20))
        #expect(first.title == "3 words to review")
        #expect(first.body.contains("session 2"))
        #expect(first.badge == 3)
        #expect(first.tab == .review)
        #expect(plan.count == ReminderPlanner.daysAhead)
    }

    @Test func skipsTodayOnceTheTimeHasPassed() throws {
        let plan = ReminderPlanner.plan(data: data(dueOn: [4]), sessions: sessions, now: day(4, hour: 21), calendar: calendar)
        #expect(try #require(plan.first).date == day(5, hour: 20))
        #expect(plan.count == ReminderPlanner.daysAhead - 1)
    }

    @Test func futureDaysCountWordsThatWillBeDueByThen() {
        let plan = ReminderPlanner.plan(data: data(dueOn: [5, 6, 6]), sessions: sessions, now: day(4), calendar: calendar)
        #expect(plan.map(\.badge).prefix(3) == [0, 1, 3])
        #expect(plan[0].tab == .today) // nothing due yet, just the session nudge
    }

    @Test func noSessionNudgeTodayAfterFinishingOne() {
        let plan = ReminderPlanner.plan(data: data(completedOn: 4), sessions: sessions, now: day(4), calendar: calendar)
        #expect(plan.first?.date == day(5, hour: 20))
        #expect(plan.first?.title == "Session 2: Me, you & us")
    }

    @Test func sessionNudgesCanBeTurnedOff() {
        var settings = ReminderSettings()
        settings.includeSessions = false
        let plan = ReminderPlanner.plan(data: data(reminders: settings, dueOn: [6]), sessions: sessions, now: day(4), calendar: calendar)
        #expect(plan.allSatisfy { $0.badge > 0 })
        #expect(plan.first?.date == day(6, hour: 20))
        #expect(plan.first?.body == "A few minutes now keeps them stuck.")
    }

    @Test func quietWhenAllSessionsAreDoneAndNothingIsDue() {
        let plan = ReminderPlanner.plan(data: data(session: 3), sessions: sessions, now: day(4), calendar: calendar)
        #expect(plan.isEmpty)
    }

    @Test func oldProgressFilesLoadWithoutReminderSettings() throws {
        let decoded = try JSONDecoder().decode(ProgressData.self, from: Data(#"{"learning":"zh","currentSession":3}"#.utf8))
        #expect(decoded.reminders == nil)
        #expect(!decoded.reminderPromptDismissed)
    }
}

@MainActor
struct WidgetTests {
    private func word(_ id: String) -> WidgetWord {
        WidgetWord(id: id, headword: id, shortWord: id, pinyin: nil, gloss: "", languageName: "German")
    }

    @Test func pinnedWordAlwaysWins() {
        let snapshot = WidgetSnapshot(pinned: word("de-haus"), pool: [word("de-ich"), word("de-du")])
        #expect(snapshot.word(for: day(4), calendar: calendar)?.id == "de-haus")
        #expect(snapshot.word(for: day(5), calendar: calendar)?.id == "de-haus")
    }

    @Test func unpinnedRotatesThroughThePoolDaily() throws {
        let snapshot = WidgetSnapshot(pinned: nil, pool: [word("a"), word("b"), word("c")])
        let ids = (1...6).compactMap { snapshot.word(for: day($0), calendar: calendar)?.id }
        #expect(Set(ids) == ["a", "b", "c"])
        #expect(ids[0] != ids[1])
        #expect(ids[0] == ids[3]) // repeats every 3 days
        #expect(WidgetSnapshot().word(for: day(4), calendar: calendar) == nil)
    }

    @Test func poolHasOnlyYourOwnTaughtWords() throws {
        let content = try ContentLibrary.loadBundled()
        let store = ProgressStore(fileURL: nil)
        store.choose(learning: .german)
        let s1 = try #require(content.session(1))
        for id in s1.de { store.toggleTaught(id) }
        store.finish(s1, now: day(4), calendar: calendar)
        store.toggleTaught("de-ich")

        #expect(Set(store.widgetPoolIDs) == Set(s1.de + ["de-ich"]))
        #expect(store.widgetPoolIDs.allSatisfy { $0.hasPrefix("de-") })
    }

    @Test func pinningTogglesAndShowsTheArticle() throws {
        let content = try ContentLibrary.loadBundled()
        let store = ProgressStore(fileURL: nil)
        store.choose(learning: .german)

        store.togglePin("de-haus")
        let snapshot = WidgetSync.snapshot(for: store.data, poolIDs: store.widgetPoolIDs, content: content)
        #expect(snapshot.pinned?.headword == "das Haus")
        #expect(snapshot.pinned?.shortWord == "Haus")

        store.togglePin("de-haus")
        #expect(store.data.pinnedWordID == nil)
    }

    @Test func widgetLabelsShowTheGrammar() throws {
        let content = try ContentLibrary.loadBundled()
        func widget(_ id: String) throws -> WidgetWord {
            WidgetSync.widgetWord(try #require(content.words[id]))
        }

        let house = try widget("de-haus")
        #expect(house.label == "das · noun")
        #expect(house.circleLabel == "das")
        #expect(house.detailLine == "house · die Häuser")

        let go = try widget("de-gehen")
        #expect(go.label == "verb")
        #expect(go.circleLabel == nil)
        #expect(go.detailLine?.hasSuffix("· er geht") == true)

        let eyes = try widget("zh-yan-jing")
        #expect(eyes.label == "yǎnjing")
        #expect(eyes.circleLabel == "yǎnjing")
        #expect(eyes.detailLine == "eye · 一双眼睛")

        let hello = try widget("de-hallo")
        #expect(hello.detailLine == hello.gloss)
    }

    @Test func oldWidgetFilesWithoutLabelsStillLoad() throws {
        let json = #"{"pool":[{"id":"de-haus","headword":"das Haus","shortWord":"Haus","gloss":"house","languageName":"German"}]}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.pool.first?.label == nil)
        #expect(snapshot.pool.first?.shortWord == "Haus")
    }
}

@MainActor
struct GrammarDrillTests {
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func word(_ content: ContentLibrary, _ id: String) throws -> Word {
        try #require(content.words[id])
    }

    @Test func germanQuestionsAreAlwaysDerDieDas() throws {
        let content = try ContentLibrary.loadBundled()
        var rng = SeededRNG(state: 1)
        let q = try #require(GrammarDrill.question(for: try word(content, "de-haus"), using: &rng))
        #expect(q.options == ["der", "die", "das"])
        #expect(q.answer == "das")
        #expect(q.isCorrect("das") && !q.isCorrect("der"))
    }

    @Test func measureWordQuestionsAcceptAlternativesAndOfferNone() throws {
        let content = try ContentLibrary.loadBundled()
        var rng = SeededRNG(state: 2)
        let door = try #require(GrammarDrill.question(for: try word(content, "zh-men"), using: &rng))
        #expect(door.answer == "扇")
        #expect(door.isCorrect("个"))  // listed under "also"
        #expect(!door.isCorrect("张"))
        #expect(door.options.count == 5)
        #expect(door.options.last == GrammarDrill.noMeasureWord)
        #expect(Set(door.options).count == 5)

        let car = try #require(GrammarDrill.question(for: try word(content, "zh-che"), using: &rng))
        #expect(car.options.contains("个"))  // the tempting wrong answer
        #expect(!car.isCorrect("个"))

        let day = try #require(GrammarDrill.question(for: try word(content, "zh-tian"), using: &rng))
        #expect(day.answer == GrammarDrill.noMeasureWord)
        #expect(day.options.count == 5)
    }

    @Test func onlyCountableNounsAreDrilled() throws {
        let content = try ContentLibrary.loadBundled()
        #expect(!GrammarDrill.isEligible(try word(content, "zh-jin-tian")))  // counting: none
        #expect(!GrammarDrill.isEligible(try word(content, "de-gehen")))
        var rng = SeededRNG(state: 3)
        let ids = ["de-haus", "de-gehen", "de-tuer", "de-hallo"]
        let round = GrammarDrill.questions(wordIDs: ids, content: content, using: &rng)
        #expect(Set(round.map(\.word.id)) == ["de-haus", "de-tuer"])
    }

    @Test func everyNounInTheContentCanBeDrilledOrIsMarkedUncountable() throws {
        let content = try ContentLibrary.loadBundled()
        for word in content.words.values where word.pos == "noun" {
            #expect(GrammarDrill.isEligible(word) || word.counting == "none", "\(word.id)")
        }
    }

    @Test func hintsAndCountingPhrases() throws {
        let content = try ContentLibrary.loadBundled()
        #expect(GenderHints.hint(for: try word(content, "de-entschuldigung")) == "Nouns ending in -ung are always die.")
        #expect(GenderHints.hint(for: try word(content, "de-name"))?.contains("exceptions") == true)
        #expect(GenderHints.hint(for: try word(content, "de-bahnhof"))?.contains("der Hof") == true)

        let car = try #require(MeasureWords.countingPhrase(for: try word(content, "zh-che")))
        #expect(car.text == "一辆车")
        #expect(car.pinyin == "yí liàng chē")
        #expect(MeasureWords.countingPhrase(for: try word(content, "zh-peng-you"))?.pinyin == "yí ge péngyou")
        #expect(MeasureWords.countingPhrase(for: try word(content, "zh-tian"))?.text == "三天")
        #expect(content.words["zh-tian"]?.grammarLine == "no measure word: 三天")
    }

    @Test func everyMeasureWordInTheContentIsExplained() throws {
        let content = try ContentLibrary.loadBundled()
        for word in content.words.values {
            guard let measure = word.measureWord else { continue }
            for mw in [measure.word] + (measure.also ?? []) {
                #expect(MeasureWords.uses[mw] != nil, "\(word.id): \(mw)")
            }
        }
        for mw in MeasureWords.distractors { #expect(MeasureWords.uses[mw] != nil, "\(mw)") }
    }
}

@MainActor
struct GrammarNotesTests {
    private func word(_ content: ContentLibrary, _ id: String) throws -> Word {
        try #require(content.words[id])
    }

    @Test func patternsExplainGenderAndMeasureWords() throws {
        let content = try ContentLibrary.loadBundled()
        #expect(GrammarNotes.pattern(for: try word(content, "de-entschuldigung")) == "Nouns ending in -ung are always die.")
        #expect(GrammarNotes.pattern(for: try word(content, "zh-che")) == "辆 is for vehicles.")
        #expect(GrammarNotes.pattern(for: try word(content, "zh-tian"))?.contains("straight in front") == true)
        #expect(GrammarNotes.pattern(for: try word(content, "zh-jin-tian")) == nil)
    }

    @Test func teacherPromptsPractiseTheGrammar() throws {
        let content = try ContentLibrary.loadBundled()
        #expect(GrammarNotes.practice(for: try word(content, "de-haus"))
                == "Say \"Haus\" on its own and have them add the article: das Haus. Then ask for two of them: zwei Häuser.")
        #expect(GrammarNotes.practice(for: try word(content, "de-gehen"))?.hasSuffix("er geht, er ist gegangen.") == true)
        #expect(GrammarNotes.practice(for: try word(content, "zh-che"))?.contains("两辆车") == true)
        #expect(GrammarNotes.practice(for: try word(content, "zh-tian"))?.contains("三天") == true)
        #expect(GrammarNotes.practice(for: try word(content, "de-hallo")) == nil)
    }

    @Test func everyMultiCharacterWordHasABreakdown() throws {
        let content = try ContentLibrary.loadBundled()
        for word in content.words.values where word.language == .chinese && word.word.count > 1 {
            #expect(word.characters?.map(\.char).joined() == word.word, "\(word.id)")
        }
    }
}

@MainActor
struct PracticeDrillTests {
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func word(_ content: ContentLibrary, _ id: String) throws -> Word {
        try #require(content.words[id])
    }

    @Test func drillsDependOnTheLanguage() {
        #expect(ChoiceDrill.drills(for: .german) == [.grammar, .plurals, .pastTense, .listening])
        #expect(ChoiceDrill.drills(for: .chinese) == [.grammar, .listening])
    }

    // MARK: Plurals

    @Test func umlauts() {
        #expect(Plurals.umlauted("Haus") == "Häus")
        #expect(Plurals.umlauted("Apfel") == "Äpfel")
        #expect(Plurals.umlauted("Bahnhof") == "Bahnhöf")
        #expect(Plurals.umlauted("Freund") == nil)
        #expect(Plurals.umlauted("Tier") == nil)
        #expect(Plurals.umlauted("Arbeit") == nil)
        #expect(Plurals.umlauted("Apotheke") == nil)
        #expect(Plurals.umlauted("Auto") == nil)
        #expect(Plurals.umlauted("Mutter") == "Mütter")
        #expect(Plurals.umlauted("Laden") == "Läden")
    }

    @Test func pluralQuestionsHaveFourDifferentOptions() throws {
        let content = try ContentLibrary.loadBundled()
        var rng = SeededRNG(state: 4)
        let house = try #require(Plurals.question(for: try word(content, "de-haus"), using: &rng))
        #expect(house.answer == "Häuser")
        #expect(house.kind == .plurals)
        #expect(Plurals.explanation(for: try word(content, "de-haus"))?.hasPrefix("It adds -er and an umlaut: die Häuser.") == true)
        #expect(!Plurals.isEligible(try word(content, "de-wasser")))  // no plural

        for word in content.words.values where Plurals.isEligible(word) {
            let q = try #require(Plurals.question(for: word, using: &rng), "\(word.id)")
            #expect(q.options.count == 4 && Set(q.options).count == 4, "\(word.id): \(q.options)")
            #expect(q.options.contains(q.answer), "\(word.id)")
            #expect(Plurals.explanation(for: word) != nil, "\(word.id)")
        }
    }

    // MARK: Past tense

    @Test func madeUpParticiplesAreTheClassicMistakes() throws {
        let content = try ContentLibrary.loadBundled()
        let cases = [
            "de-gehen": "gegeht",          // irregular → regular -t
            "de-machen": "gemachen",       // regular → -en
            "de-aufstehen": "aufgesteht",  // ge- after the prefix
            "de-verstehen": "geverstanden",  // no ge- → a stray one
            "de-reparieren": "gerepariert",
            "de-arbeiten": "gearbeiten",
        ]
        for (id, expected) in cases {
            #expect(PastTense.madeUpParticiple(for: try word(content, id)) == expected, "\(id)")
        }
        #expect(PastTense.gePlacement(infinitive: "vergessen", participle: "vergessen") == .none)
        #expect(PastTense.gePlacement(infinitive: "gewinnen", participle: "gewonnen") == .none)
        #expect(PastTense.gePlacement(infinitive: "geben", participle: "gegeben") == .front)
        #expect(PastTense.gePlacement(infinitive: "anrufen", participle: "angerufen") == .afterPrefix("an"))
    }

    @Test func pastTenseQuestionsMixHabenAndSein() throws {
        let content = try ContentLibrary.loadBundled()
        var rng = SeededRNG(state: 5)
        let go = try #require(PastTense.question(for: try word(content, "de-gehen"), using: &rng))
        #expect(go.answer == "ist gegangen")
        #expect(Set(go.options) == ["ist gegangen", "hat gegangen", "ist gegeht", "hat gegeht"])
        #expect(PastTense.explanation(for: try word(content, "de-gehen"))?.contains("sein") == true)
        #expect(!PastTense.isEligible(try word(content, "de-koennen")))  // modal
        #expect(!PastTense.isEligible(try word(content, "de-sein")))  // taught as "ist"

        for word in content.words.values where PastTense.isEligible(word) {
            let q = try #require(PastTense.question(for: word, using: &rng), "\(word.id)")
            #expect(Set(q.options).count == 4, "\(word.id): \(q.options)")
        }
    }

    // MARK: Listening

    @Test func listeningOffersFourDifferentMeanings() throws {
        let content = try ContentLibrary.loadBundled()
        var rng = SeededRNG(state: 6)
        let house = try word(content, "de-haus")
        // Knowing only one word still works: the wrong answers come from the rest of the content.
        let q = try #require(Listening.question(for: house, pool: [house], content: content, using: &rng))
        #expect(q.answer == "house")
        #expect(Set(q.options.map { $0.lowercased() }).count == 4)

        let ids = content.sessions.prefix(3).flatMap(\.zh)
        let round = ChoiceDrill.listening.questions(wordIDs: ids, content: content, using: &rng)
        #expect(round.count == ids.count)
        for question in round {
            #expect(question.options.count == 4)
            #expect(question.options.contains(question.answer))
        }
    }

    // MARK: Sentences

    @Test func pinyinSyllablesCountCharacters() {
        #expect(SentenceBuilder.characterCount(forPinyin: "fángjiān") == 2)
        #expect(SentenceBuilder.characterCount(forPinyin: "yìdiǎnr") == 3)
        #expect(SentenceBuilder.characterCount(forPinyin: "zhèr") == 2)
        #expect(SentenceBuilder.characterCount(forPinyin: "èr") == 1)
        #expect(SentenceBuilder.characterCount(forPinyin: "Wǎn'ān") == 2)
        #expect(SentenceBuilder.characterCount(forPinyin: "nǚ'ér") == 2)
        #expect(SentenceBuilder.characterCount(forPinyin: "péngyou") == 2)
    }

    @Test func chineseSentencesSplitAlongThePinyin() throws {
        let content = try ContentLibrary.loadBundled()
        let room = try word(content, "zh-fang-jian")
        let tiles = try #require(SentenceBuilder.tiles(for: room.examples[0], language: .chinese, content: content))
        #expect(tiles.map(\.text) == ["我", "的", "房间", "很", "小"])
        #expect(tiles.map(\.pinyin) == ["wǒ", "de", "fángjiān", "hěn", "xiǎo"])

        let little = try word(content, "zh-yi-dian-er")
        let littleTiles = try #require(SentenceBuilder.tiles(for: little.examples[0], language: .chinese, content: content))
        #expect(littleTiles.map(\.text) == ["我", "会", "说", "一点儿", "中文"])
        #expect(littleTiles.last?.pinyin == "Zhōngwén")
    }

    @Test func germanSentencesHideTheCapitalOnlyWhenItGivesTheGameAway() throws {
        let content = try ContentLibrary.loadBundled()
        let house = try word(content, "de-haus")
        let tiles = try #require(SentenceBuilder.tiles(for: house.examples[0], language: .german, content: content))
        #expect(tiles.map(\.text) == ["das", "Haus", "ist", "groß"])

        var rng = SeededRNG(state: 7)
        let puzzle = try #require(SentenceBuilder.puzzle(for: house, content: content, using: &rng))
        #expect(!puzzle.isCorrect(puzzle.shuffled))
        #expect(puzzle.isCorrect(puzzle.tiles))
    }

    @Test func almostEverySentenceCanBeBuilt() throws {
        let content = try ContentLibrary.loadBundled()
        for language in Language.allCases {
            let words = content.words.values.filter { $0.language == language }
            let usable = words.filter { SentenceBuilder.isEligible($0, content: content) }
            // Only two-word sentences ("Danke schön!") are left out.
            #expect(Double(usable.count) / Double(words.count) > 0.9, "\(language): \(usable.count) of \(words.count)")
            for word in usable {
                let tiles = try #require(SentenceBuilder.tiles(for: word.examples[0], language: language, content: content))
                let joined = tiles.map(\.text).joined(separator: language == .german ? " " : "")
                let letters = { (s: String) in s.filter { $0.isLetter || $0.isNumber }.lowercased() }
                #expect(letters(joined) == letters(word.examples[0].text), "\(word.id)")
            }
        }
    }
}

@MainActor
struct PracticeDrillEdgeCaseTests {
    @Test func edgeCases() throws {
        let content = try ContentLibrary.loadBundled()
        let lose = try #require(content.words["de-verlieren"])
        #expect(PastTense.explanation(for: lose)?.contains("-ieren") == false)
        let stay = try #require(content.words["de-bleiben"])
        #expect(PastTense.explanation(for: stay)?.contains("exception") == true)

        #expect(Plurals.endsInUnstressedSyllable("vogel"))
        #expect(!Plurals.endsInUnstressedSyllable("spiel"))
        #expect(!Plurals.endsInUnstressedSyllable("meer"))
        var rng = SystemRandomNumberGenerator()
        let wordWord = try #require(content.words["de-wort"])
        for _ in 0..<20 {
            let question = try #require(Plurals.question(for: wordWord, using: &rng))
            #expect(!question.options.contains("Worte"))
        }

        // "Kannst du …?" starts lower-case: kannst is never a noun.
        for word in content.words.values where word.language == .german {
            guard let first = SentenceBuilder.tiles(for: word.examples[0], language: .german, content: content)?.first?.text
            else { continue }
            #expect(!["Kannst", "Können", "Woher", "Mach", "Zuerst"].contains(first), "\(word.id)")
        }
    }
}
