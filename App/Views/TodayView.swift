import SwiftUI

struct TodayView: View {
    let learning: Language

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @State private var showingSettings = false
    @State private var finishedSession: Session?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if let session = content.session(progress.currentSession) {
                            sessionBody(session)
                        } else {
                            allDone
                        }
                    }
                    .padding(16)
                    .id("top")
                }
                // A new session should start at the top, not where the Finish button was.
                .onChange(of: progress.currentSession) {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
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

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Try this together").font(.subheadline.weight(.semibold))
                Text(session.conversationStarter).font(.subheadline)
            }
        }
        .card()

        SectionTitle(
            title: "You're learning \(learning.name)",
            subtitle: "Your partner teaches you these. Mark each one once you've been taught it."
        )
        ForEach(content.words(in: session, language: learning)) { word in
            LearnerCard(word: word, taught: progress.isTaught(word.id)) {
                withAnimation(.snappy) { progress.toggleTaught(word.id) }
            }
        }

        SectionTitle(
            title: "You're teaching \(learning.other.name)",
            subtitle: "Your partner's words. Tap one for teaching notes."
        )
        ForEach(content.words(in: session, language: learning.other)) { word in
            TeacherRow(word: word)
        }

        finishButton(session)
    }

    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session \(session.number) of \(content.sessionCount)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Text(session.theme)
                .font(.largeTitle.bold())
            HStack(spacing: 12) {
                Label("\(progress.completedCount) done", systemImage: "checkmark.seal")
                let streak = progress.streak()
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finishButton(_ session: Session) -> some View {
        let ready = progress.canFinish(session)
        let remaining = session.wordIDs(for: learning).filter { !progress.isTaught($0) }.count
        return VStack(spacing: 8) {
            Button {
                progress.finish(session)
                finishedSession = session
            } label: {
                Text("Finish session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!ready)

            Text(ready
                 ? "Finishing adds your 5 words to review and moves you to the next session."
                 : "\(remaining) of your words still to be taught.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
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

/// One of *your* words. The meaning stays hidden until your partner has taught it.
struct LearnerCard: View {
    let word: Word
    let taught: Bool
    let onToggle: () -> Void

    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                HeadwordView(word: word)
                Spacer()
                SpeakButton(word: word)
            }

            if taught {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.gloss).font(.title3.weight(.medium))
                    if let grammar = word.grammarLine {
                        Text(grammar).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let example = word.examples.first {
                    ExampleView(example: example, language: word.language)
                }
                HStack {
                    Button("More about this word") { showingDetail = true }
                    Spacer()
                    Button("Hide meaning", action: onToggle)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            } else {
                Label("Ask your partner to teach you this one", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: onToggle) {
                    Label("I've been taught this", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(taught ? Color.green.opacity(0.5) : .clear, lineWidth: 2)
        }
        .sheet(isPresented: $showingDetail) {
            WordDetailView(word: word, isTeaching: false)
        }
    }
}

/// One of your partner's words: everything visible, tap for teaching notes.
struct TeacherRow: View {
    let word: Word
    @State private var showingDetail = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HeadwordView(word: word, style: .medium)
                Text(word.gloss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SpeakButton(word: word, size: .body)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 14)
        .contentShape(.rect)
        .onTapGesture { showingDetail = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows teaching notes")
        .sheet(isPresented: $showingDetail) {
            WordDetailView(word: word, isTeaching: true)
        }
    }
}
