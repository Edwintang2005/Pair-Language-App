import SwiftUI

/// Every word so far, from session 1 up to the current one: yours and your partner's.
struct LibraryView: View {
    let learning: Language

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content

    @State private var showingTeaching = false
    @State private var search = ""
    @State private var selected: Word?

    private var language: Language { showingTeaching ? learning.other : learning }

    private var visibleSessions: [Session] {
        let last = min(progress.currentSession, content.sessionCount)
        return content.sessions.filter { $0.number <= last }.reversed()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Words", selection: $showingTeaching) {
                        Text("Learning \(learning.name)").tag(false)
                        Text("Teaching \(learning.other.name)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                ForEach(visibleSessions) { session in
                    let words = content.words(in: session, language: language).filter { $0.matches(search) }
                    if !words.isEmpty {
                        Section {
                            ForEach(words) { word in row(word) }
                        } header: {
                            Text("Session \(session.number) · \(session.theme)")
                        }
                    }
                }
            }
            .navigationTitle("Words")
            .searchable(text: $search, prompt: "Search words or meanings")
            .sheet(item: $selected) { word in
                WordDetailView(word: word, isTeaching: showingTeaching)
            }
            .overlay {
                if visibleSessions.isEmpty {
                    ContentUnavailableView("No words yet", systemImage: "books.vertical")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ word: Word) -> some View {
        // Your own words stay hidden until your partner has taught them.
        let hidden = !showingTeaching && !progress.isLearned(word.id) && !progress.isTaught(word.id)
        Button {
            selected = word
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HeadwordView(word: word, style: .medium)
                    Text(hidden ? "Not taught yet" : word.gloss)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !showingTeaching, let state = progress.review(for: word.id) {
                    StrengthBadge(strength: Scheduler.strength(of: state))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(hidden)
    }
}
