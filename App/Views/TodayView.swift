import SwiftUI

struct TodayView: View {
    let learning: Language

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @State private var showingSettings = false
    @State private var finishedSession: Session?
    @State private var starterExpanded = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if let session = content.session(progress.currentSession) {
                            sessionBody(session)
                        } else {
                            allDone
                        }
                    }
                    .padding(16)
                    .id("top")
                }
                // A new session should start at the top, not where you left off.
                .onChange(of: progress.currentSession) {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .background(Color(.systemGroupedBackground))
            // Finish stays on screen, so you never have to scroll to move on.
            .safeAreaInset(edge: .bottom) {
                if let session = content.session(progress.currentSession) {
                    finishBar(session)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .alert(
                "Session \(finishedSession?.number ?? 0) complete",
                isPresented: Binding(get: { finishedSession != nil }, set: { if !$0 { finishedSession = nil } })
            ) {
                Button("Nice") { finishedSession = nil }
            } message: {
                Text("5 new words added to your review. Remember to finish the session on your partner's phone too.")
            }
        }
    }

    @ViewBuilder
    private func sessionBody(_ session: Session) -> some View {
        header(session)

        if progress.showsReminderPrompt {
            reminderPrompt
        }

        starter(session)

        SectionTitle(
            title: "Your \(learning.name) words",
            subtitle: "Tap Taught once your partner has taught you each one."
        )
        ForEach(content.words(in: session, language: learning)) { word in
            LearnerRow(word: word, taught: progress.isTaught(word.id)) {
                withAnimation(.snappy) { progress.toggleTaught(word.id) }
            }
        }

        SectionTitle(
            title: "Teach them \(learning.other.name)",
            subtitle: "Tap a word for teaching notes."
        )
        let partnerWords = content.words(in: session, language: learning.other)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                 count: learning.other == .chinese ? 3 : 2),
                  spacing: 10) {
            ForEach(partnerWords) { word in
                TeacherTile(word: word)
            }
        }
    }

    private func header(_ session: Session) -> some View {
        let taught = taughtCount(session)
        let total = session.wordIDs(for: learning).count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Session \(session.number) of \(content.sessionCount)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.tint)
                .background(Color.accentColor.opacity(0.12), in: .capsule)
            Text(session.theme)
                .font(.largeTitle.bold())
            HStack(spacing: 6) {
                let streak = progress.streak()
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("·")
                }
                Text("\(taught) of \(total) taught")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ProgressView(value: Double(taught), total: Double(max(total, 1)))
                .tint(.green)
                .accessibilityLabel("\(taught) of \(total) words taught")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func starter(_ session: Session) -> some View {
        Button {
            withAnimation(.snappy) { starterExpanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try this together").font(.subheadline.weight(.semibold))
                    Text(session.conversationStarter)
                        .font(.subheadline)
                        .lineLimit(starterExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: starterExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityHint(starterExpanded ? "Shows less" : "Shows the whole activity")
    }

    private var reminderPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get a daily nudge").font(.subheadline.weight(.semibold))
                    Text("One reminder in the evening when words are due or your next session is waiting.")
                        .font(.subheadline)
                }
            }
            HStack {
                Button("Turn on reminders") {
                    Task {
                        if await ReminderScheduler.requestPermission() {
                            progress.setReminders(ReminderSettings())
                        } else {
                            progress.dismissReminderPrompt()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Not now") { progress.dismissReminderPrompt() }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
        .card()
    }

    private func taughtCount(_ session: Session) -> Int {
        session.wordIDs(for: learning).filter(progress.isTaught).count
    }

    private func finishBar(_ session: Session) -> some View {
        let ready = progress.canFinish(session)
        let remaining = session.wordIDs(for: learning).count - taughtCount(session)
        return Button {
            progress.finish(session)
            finishedSession = session
        } label: {
            Text(ready ? "Finish session" : "Finish session · \(remaining) to go")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!ready)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        // Solid backing, so the words scrolling underneath don't show through the button.
        .background(Color(.systemGroupedBackground).opacity(0.97))
        .accessibilityHint(ready
            ? "Adds your words to review and moves you both to the next session"
            : "Mark all your words as taught first")
    }

    private var allDone: some View {
        VStack(spacing: 12) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("All sessions finished")
                .font(.title2.bold())
            Text("You've finished all \(content.sessionCount) sessions available so far. More arrive as the word list grows. Keep reviewing until then.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }

}

/// One of *your* words, as a compact row. The meaning stays hidden until your partner has taught it.
struct LearnerRow: View {
    let word: Word
    let taught: Bool
    let onToggle: () -> Void

    @State private var showingDetail = false

    private var meaningLine: String {
        [word.gloss, word.grammarLine].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HeadwordView(word: word, style: .medium)
                Text(taught ? meaningLine : "Not taught yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            SpeakButton(word: word, size: .body)
            if taught {
                Button(action: onToggle) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Taught")
                .accessibilityHint("Hides the meaning again")
            } else {
                Button("Taught", action: onToggle)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityHint("Shows the meaning")
            }
        }
        .card(padding: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(taught ? Color.green.opacity(0.45) : .clear, lineWidth: 1.5)
        }
        .contentShape(.rect)
        // Once taught, the row opens the full word: examples, grammar and tips.
        .onTapGesture { if taught { showingDetail = true } }
        .accessibilityAddTraits(taught ? .isButton : [])
        .sheet(isPresented: $showingDetail) {
            WordDetailView(word: word, isTeaching: false)
        }
    }
}

/// One of your partner's words, as a small tile. Tap for teaching notes.
struct TeacherTile: View {
    let word: Word
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(spacing: 2) {
                if let noun = word.noun {
                    Text("\(Text(noun.article).foregroundStyle(Color.gender(noun.gender))) \(word.word)")
                        .font(.headline)
                } else {
                    Text(word.word)
                        .font(word.language == .chinese ? .title2.weight(.semibold) : .headline)
                }
                if let pinyin = word.pinyin {
                    Text(pinyin).font(.caption).foregroundStyle(.secondary)
                }
                Text(word.shortGloss)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows teaching notes")
        .sheet(isPresented: $showingDetail) {
            WordDetailView(word: word, isTeaching: true)
        }
    }
}
