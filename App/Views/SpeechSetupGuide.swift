import SwiftUI

/// How to get the speaking check working, for whatever's stopping it: permission switched off, or
/// the language not downloaded for offline recognition yet. Used in the speaking drill and Settings.
struct SpeechSetupGuide: View {
    let availability: SpeechCheck.Availability
    let language: Language
    /// "Check again", for after the steps. Nil hides the button.
    var onRecheck: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(.orange)
            }
            .font(.subheadline.weight(.semibold))
            if let intro {
                Text(intro).font(.subheadline)
            }
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(step).font(.subheadline)
                        }
                    }
                }
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if availability == .needsPermission {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let onRecheck, availability != .unsupported {
                    Button("Check again", action: onRecheck)
                        .buttonStyle(.bordered)
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonBorderShape(.capsule)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private var title: String {
        switch availability {
        case .ready: "Checking is ready"
        case .needsPermission: "Turn on speech recognition for Pair"
        case .needsDownload: "Set up checking for \(language.name)"
        case .unsupported: "Checking isn't available for \(language.name)"
        case .busy: "Speech recognition is getting ready"
        }
    }

    private var icon: String {
        switch availability {
        case .ready: "checkmark.circle.fill"
        case .needsPermission: "hand.raised.fill"
        case .needsDownload: "arrow.down.circle.fill"
        case .unsupported: "info.circle.fill"
        case .busy: "hourglass"
        }
    }

    private var intro: String? {
        switch availability {
        case .needsDownload:
            "Pair only checks your speaking offline, so your iPhone needs \(language.name) downloaded for dictation first. It's free and takes a few minutes:"
        case .needsPermission:
            "Speech recognition is switched off for Pair, so it can't show which words it understood."
        case .unsupported:
            "Your iPhone can't recognise \(language.name). You can still compare the two recordings by ear."
        case .busy:
            "Your iPhone is still setting up speech recognition. Try again in a moment."
        case .ready:
            nil
        }
    }

    private var steps: [String] {
        switch availability {
        case .needsDownload:
            [
                "Open the Settings app and go to General → Keyboard → Keyboards → Add New Keyboard.",
                "Add \(keyboardName).",
                "Back in General → Keyboard, turn on Enable Dictation. If you see a Dictation Languages list, tick \(dictationName).",
                "Stay on Wi‑Fi for a few minutes while your iPhone downloads it, then come back and tap Check again.",
            ]
        case .needsPermission:
            [
                "Tap Open Settings below.",
                "Turn on Speech Recognition, then come back to Pair.",
            ]
        default:
            []
        }
    }

    private var note: String? {
        switch availability {
        case .needsDownload:
            "Some older iPhones can't recognise \(language.name) offline at all. If it's still not available after this, compare by ear: that works just as well."
        case .needsPermission:
            "If the switch is greyed out, Screen Time may be blocking it: check Settings → Screen Time → Content & Privacy Restrictions → Speech Recognition."
        default:
            nil
        }
    }

    /// The keyboard to add, as iOS names it.
    private var keyboardName: String {
        language == .chinese ? "Chinese, Simplified (Pinyin – QWERTY)" : "German (Germany)"
    }

    /// The dictation language to tick, as iOS names it.
    private var dictationName: String {
        language == .chinese ? "Mandarin (China mainland)" : "German (Germany)"
    }
}

/// Settings → Speaking practice → Set it up.
struct SpeechSetupView: View {
    let language: Language

    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: SpeechCheck.Availability = .ready

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if availability == .ready {
                    Label("Checking is ready for \(language.name). Record yourself in Speaking to try it.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .card()
                } else {
                    SpeechSetupGuide(availability: availability, language: language, onRecheck: refresh)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Speaking check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        // Coming back from the Settings app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        withAnimation { availability = SpeechCheck.availability(locale: language.speechCode) }
    }
}
