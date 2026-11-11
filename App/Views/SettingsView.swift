import SwiftUI

struct SettingsView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @Environment(\.openURL) private var openURL

    @AppStorage(AppSettings.checksSpeaking) private var checksSpeaking = true
    @State private var speechAvailability: SpeechCheck.Availability = .ready
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingReset = false
    @State private var confirmingSwitch = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                if let learning = progress.learning {
                    Section {
                        LabeledContent("Learning", value: "\(learning.flag) \(learning.name)")
                        LabeledContent("Teaching", value: "\(learning.other.flag) \(learning.other.name)")
                        Button("Switch languages") { confirmingSwitch = true }
                    } header: {
                        Text("This phone")
                    }
                }

                remindersSection

                Section {
                    Toggle("Check my speaking", isOn: $checksSpeaking)
                    if checksSpeaking, let learning = progress.learning {
                        NavigationLink {
                            SpeechSetupView(language: learning)
                        } label: {
                            speechStatus(for: learning)
                        }
                    }
                } header: {
                    Text("Speaking practice")
                } footer: {
                    Text("After you record yourself, your iPhone's speech recognition shows which words it understood. It only runs offline, so your voice never leaves your phone. Without it, you compare by ear.")
                }

                Section {
                    Stepper(value: Binding(
                        get: { progress.currentSession },
                        set: { progress.setCurrentSession($0) }
                    ), in: 1...(content.sessionCount + 1)) {
                        LabeledContent("Current session", value: "\(progress.currentSession)")
                    }
                } header: {
                    Text("Keeping in step")
                } footer: {
                    Text("Both phones should show the same session. If one of you gets ahead, set this to match. Your review history isn't affected.")
                }

                Section("Progress") {
                    LabeledContent("Sessions finished", value: "\(progress.completedCount)")
                    LabeledContent("Words learned", value: "\(progress.learnedCount)")
                    LabeledContent("Strong words", value: "\(progress.strongCount())")
                    LabeledContent("Current streak", value: "\(progress.streak()) days")
                }

                Section("About") {
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: AppLinks.support) {
                        Label("Help and support", systemImage: "questionmark.circle")
                    }
                    Link(destination: AppLinks.email) {
                        Label("Report a mistake or send feedback", systemImage: "envelope")
                    }
                    LabeledContent("Version", value: AppLinks.version)
                }

                Section {
                    Button("Reset all progress", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("Everything is stored only on this phone. There's no account and no server.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { notificationsDenied = await ReminderScheduler.isDenied() }
            .onAppear(perform: refreshSpeechAvailability)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshSpeechAvailability() }
            }
            .onChange(of: progress.learning) { refreshSpeechAvailability() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Switch languages?", isPresented: $confirmingSwitch, titleVisibility: .visible) {
                if let learning = progress.learning {
                    Button("Learn \(learning.other.name) instead") {
                        progress.choose(learning: learning.other)
                    }
                }
            } message: {
                Text("This phone will treat the other language as yours. Your session number and review history stay as they are.")
            }
            .confirmationDialog("Reset all progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) {
                    progress.resetAll()
                    dismiss()
                }
            } message: {
                Text("This deletes your sessions, streak and review history on this phone. It can't be undone.")
            }
        }
    }

    // MARK: Speaking

    /// "Ready for Chinese", or what needs doing first.
    @ViewBuilder
    private func speechStatus(for language: Language) -> some View {
        switch speechAvailability {
        case .ready:
            Label("Ready for \(language.name)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsPermission:
            Label("Turn on speech recognition", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .needsDownload:
            Label("Set up for \(language.name)", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.orange)
        case .unsupported:
            Label("Not available for \(language.name)", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .busy:
            Label("Getting ready…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshSpeechAvailability() {
        guard let learning = progress.learning else { return }
        speechAvailability = SpeechCheck.availability(locale: learning.speechCode)
    }

    // MARK: Reminders

    private var reminders: ReminderSettings { progress.reminders ?? ReminderSettings(enabled: false) }

    private var remindersSection: some View {
        Section {
            Toggle("Daily reminder", isOn: Binding(
                get: { reminders.enabled && !notificationsDenied },
                set: { setEnabled($0) }
            ))
            if reminders.enabled && !notificationsDenied {
                DatePicker("Time", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: reminders.hour, minute: reminders.minute, second: 0, of: .now) ?? .now },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        var updated = reminders
                        updated.hour = parts.hour ?? 20
                        updated.minute = parts.minute ?? 0
                        progress.setReminders(updated)
                    }
                ), displayedComponents: .hourAndMinute)
                Toggle("Remind me about sessions", isOn: Binding(
                    get: { reminders.includeSessions },
                    set: { value in
                        var updated = reminders
                        updated.includeSessions = value
                        progress.setReminders(updated)
                    }
                ))
            }
            if notificationsDenied {
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if notificationsDenied {
                Text("Notifications are turned off for Pair in the Settings app.")
            } else {
                Text("At most one notification a day: when words are due for review, or your next session hasn't been done yet.")
            }
        }
    }

    private func setEnabled(_ enabled: Bool) {
        var updated = reminders
        guard enabled else {
            updated.enabled = false
            progress.setReminders(updated)
            return
        }
        Task {
            if await ReminderScheduler.requestPermission() {
                updated.enabled = true
                progress.setReminders(updated)
            } else {
                notificationsDenied = true
            }
        }
    }
}

/// Where the app's web pages live (served by GitHub Pages from the repo's docs folder).
enum AppLinks {
    static let privacyPolicy = URL(string: "https://edwintang2005.github.io/Pair-Language-App/privacy.html")!
    static let support = URL(string: "https://edwintang2005.github.io/Pair-Language-App/")!
    static let email = URL(string: "mailto:edwintang2005@gmail.com?subject=Pair%20feedback")!

    /// "1.0 (12)": the App Store version and build number.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
