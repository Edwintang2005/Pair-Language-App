import Foundation
import Observation
import UserNotifications

/// The user's reminder preferences, stored with the rest of their progress.
struct ReminderSettings: Codable, Equatable {
    var enabled = true
    var hour = 20
    var minute = 0
    /// Also nudge when the next session hasn't been done today.
    var includeSessions = true
}

enum AppTab: String, Hashable {
    case today, review, words
}

/// One notification we intend to deliver.
struct PlannedReminder: Equatable {
    let date: Date
    let title: String
    let body: String
    let badge: Int
    let tab: AppTab
}

/// Works out the next week of reminders from the current progress. Pure, so it's easy to test.
///
/// Local notifications can't run code when they fire, so each day's message (how many words are due)
/// is computed ahead of time. The app recomputes whenever progress changes or it comes to the foreground.
enum ReminderPlanner {
    static let daysAhead = 7

    static func plan(data: ProgressData, sessions: [Session], now: Date,
                     calendar: Calendar = .current) -> [PlannedReminder] {
        guard let settings = data.reminders, settings.enabled, data.learning != nil else { return [] }

        let session = sessions.first { $0.number == data.currentSession }
        let finishedToday = data.completed.values.contains { calendar.isDate($0, inSameDayAs: now) }
        let today = calendar.startOfDay(for: now)

        var result: [PlannedReminder] = []
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day),
                  fire > now else { continue }

            let due = data.reviews.values.filter { $0.due <= fire }.count
            // Only today's state is known; on later days assume the next session is still waiting.
            let pendingSession = settings.includeSessions && !(offset == 0 && finishedToday) ? session : nil

            if due > 0 {
                let body = if let pendingSession {
                    "Then session \(pendingSession.number), \(pendingSession.theme), is ready for you both."
                } else {
                    "A few minutes now keeps them stuck."
                }
                result.append(PlannedReminder(
                    date: fire,
                    title: "\(due) word\(due == 1 ? "" : "s") to review",
                    body: body,
                    badge: due,
                    tab: .review
                ))
            } else if let pendingSession {
                result.append(PlannedReminder(
                    date: fire,
                    title: "Session \(pendingSession.number): \(pendingSession.theme)",
                    body: "Ready when you both are. Five words each.",
                    badge: 0,
                    tab: .today
                ))
            }
        }
        return result
    }
}

/// Talks to the system notification centre.
enum ReminderScheduler {
    private static var center: UNUserNotificationCenter { .current() }

    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Replaces all pending reminders and updates the app badge.
    static func refresh(data: ProgressData, sessions: [Session], now: Date = .now) async {
        center.removeAllPendingNotificationRequests()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let enabled = data.reminders?.enabled == true
        let dueNow = data.reviews.values.filter { $0.due <= now }.count
        try? await center.setBadgeCount(enabled ? dueNow : 0)

        let calendar = Calendar.current
        for (index, reminder) in ReminderPlanner.plan(data: data, sessions: sessions, now: now).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.badge = NSNumber(value: reminder.badge)
            content.userInfo = ["tab": reminder.tab.rawValue]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "pair.reminder.\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }
}

/// Receives notification taps and tells the UI which tab to open.
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var requestedTab: AppTab?

    // Use the completion-handler versions, not the async ones. With the async versions, iOS runs the
    // completion off the main thread, and UIKit aborts when a notification tap launches the app.

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["tab"] as? String
        let done = MainThreadCallback(completionHandler)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.requestedTab = raw.flatMap(AppTab.init(rawValue:))
            }
            done.run()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

/// Carries a system completion handler to the main queue. Only ever called there, once.
nonisolated private struct MainThreadCallback: @unchecked Sendable {
    private let callback: () -> Void
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    func run() { callback() }
}
