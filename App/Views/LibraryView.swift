import SwiftUI

/// Every word so far, from session 1 up to the current one: yours and your partner's.
/// Your own words only appear once your partner has taught them.
struct LibraryView: View {
    let learning: Language

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content

    @State private var showingTeaching = false
    @State private var search = ""
    @State private var selected: Word?

    private var language: Language { showingTeaching ? learning.other : learning }

    /// Sessions up to the current one, newest first, each with the words that should be shown.
    private var sections: [(session: Session, words: [Word])] {
        let last = min(progress.currentSession, content.sessionCount)
        return content.sessions
            .filter { $0.number <= last }
            .reversed()
            .map { session in
                let words = content.words(in: session, language: language).filter { word in
                    (showingTeaching || progress.isLearned(word.id) || progress.isTaught(word.id))
                        && word.matches(search)
                }
                return (session, words)
            }
            .filter { !$0.words.isEmpty }
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

                ForEach(sections, id: \.session.id) { section in
                    Section {
                        ForEach(section.words) { word in row(word) }
                    } header: {
                        Text("Session \(section.session.number) · \(section.session.theme)")
                    }
                }
            }
            .navigationTitle("Words")
            .searchable(text: $search, prompt: "Search words or meanings")
            .sheet(item: $selected) { word in
                WordDetailView(word: word, isTeaching: showingTeaching)
            }
            .overlay {
                if sections.isEmpty {
                    if !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView(
                            "No words yet",
                            systemImage: "books.vertical",
                            description: Text("Your words appear here once your partner has taught them.")
                        )
                    }
                }
            }
        }
    }

    private func row(_ word: Word) -> some View {
        Button {
            selected = word
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HeadwordView(word: word, style: .medium)
                    Text(word.gloss)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if progress.data.pinnedWordID == word.id {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shown on Lock Screen")
                }
                if !showingTeaching, let state = progress.review(for: word.id) {
                    StrengthBadge(strength: Scheduler.strength(of: state))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
