import SwiftUI
import UserNotifications

@main
struct PairApp: App {
    @State private var progress = ProgressStore.live()
    private let content: ContentLibrary
    /// Held here for the app's lifetime: the notification centre only keeps a weak reference.
    private let router = NotificationRouter()

    init() {
        do {
            content = try ContentLibrary.loadBundled()
        } catch {
            // The word lists ship inside the app, so this only happens if the build is broken.
            fatalError("Could not load bundled content: \(error)")
        }
        // Set before launch finishes, so tapping a notification on a cold start still opens the right tab.
        UNUserNotificationCenter.current().delegate = router
        // Recordings are deleted as you go; this catches any left by a run that ended abruptly.
        VoiceRecorder.removeLeftoverRecordings()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(progress)
                .environment(content)
                .environment(router)
        }
    }
}

struct RootView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @Environment(NotificationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .today
    /// Bumped whenever the app comes to the foreground, so reminders are re-planned for the new day.
    @State private var foregroundCount = 0
    /// The day the screens were last drawn for. When it changes (the app was left open overnight),
    /// Today and Review are rebuilt so "due", the streak and "next review" are right.
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
        Group {
            if let learning = progress.learning {
                TabView(selection: $tab) {
                    TodayView(learning: learning)
                        .id(today)
                        .tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(AppTab.today)
                    ReviewView()
                        .id(today)
                        .tabItem { Label("Review", systemImage: "rectangle.on.rectangle.angled") }
                        .badge(progress.dueWordIDs().count)
                        .tag(AppTab.review)
                    LibraryView(learning: learning)
                        .tabItem { Label("Words", systemImage: "books.vertical") }
                        .tag(AppTab.words)
                }
            } else {
                OnboardingView()
            }
        }
        // Any change to progress (a finished session, a review, new settings) re-plans the reminders.
        .task(id: RefreshKey(data: progress.data, foregroundCount: foregroundCount)) {
            // Grading a round of cards changes progress many times a second: wait for it to settle.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            WidgetSync.update(progress: progress, content: content)
            await ReminderScheduler.refresh(data: progress.data, sessions: content.sessions)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                foregroundCount += 1
                let now = Calendar.current.startOfDay(for: .now)
                if now != today { today = now }
                ReminderScheduler.clearDelivered()
            }
        }
        // `initial`: a notification tapped on a cold start can set the tab before the first render.
        .onChange(of: router.requestedTab, initial: true) { _, requested in
            guard let requested else { return }
            tab = requested
            router.requestedTab = nil
        }
    }

    private struct RefreshKey: Equatable {
        let data: ProgressData
        let foregroundCount: Int
    }
}
