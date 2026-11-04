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
        #expect(content.sessionCount >= 20)
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
