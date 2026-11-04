import SwiftUI

/// Choose which sessions to test yourself on, and which way round the cards go.
struct PracticeSetupView: View {
    enum Direction: String, CaseIterable, Identifiable {
        case toEnglish, fromEnglish, mixed
        var id: String { rawValue }
    }

    let learning: Language

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var direction: Direction = .toEnglish
    @State private var selected: Set<Int> = []
    @State private var drillCards: [DrillCard] = []
    @State private var drilling = false

    /// Sessions with at least one of your words that you've been taught, newest first.
    private var sessions: [(session: Session, words: [Word])] {
        content.sessions.reversed().compactMap { session in
            let words = content.words(in: session, language: learning)
                .filter { progress.isLearned($0.id) || progress.isTaught($0.id) }
            return words.isEmpty ? nil : (session, words)
        }
    }

    private var selectedWords: [Word] {
        sessions.filter { selected.contains($0.session.number) }.flatMap(\.words)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Which way round") {
                    Picker("Direction", selection: $direction) {
                        ForEach(Direction.allCases) { option in
                            Text(label(for: option)).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    ForEach(sessions, id: \.session.id) { item in
                        Button {
                            toggle(item.session.number)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Session \(item.session.number) · \(item.session.theme)")
                                        .foregroundStyle(.primary)
                                    Text("\(item.words.count) word\(item.words.count == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(item.session.number) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(item.session.number) ? Color.accentColor : Color.secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(item.session.number) ? .isSelected : [])
                    }
                } header: {
                    HStack {
                        Text("Sessions")
                        Spacer()
                        Button(selected.count == sessions.count ? "Select none" : "Select all") {
                            selected = selected.count == sessions.count ? [] : Set(sessions.map(\.session.number))
                        }
                        .font(.subheadline)
                        .textCase(nil)
                    }
                } footer: {
                    Text("Testing yourself doesn't change when words are next due for review.")
                }
            }
            .navigationTitle("Test yourself")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    drillCards = makeCards()
                    drilling = true
                } label: {
                    Text(selectedWords.isEmpty ? "Choose a session" : "Start · \(selectedWords.count) cards")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedWords.isEmpty)
                .padding(16)
                .background(.bar)
            }
            .navigationDestination(isPresented: $drilling) {
                DrillView(title: "Test yourself", kind: .selfTest, cards: drillCards)
            }
            .onAppear {
                if selected.isEmpty { selected = Set(sessions.map(\.session.number)) }
            }
        }
    }

    private func label(for option: Direction) -> String {
        switch option {
        case .toEnglish: "\(learning.name) → English"
        case .fromEnglish: "English → \(learning.name)"
        case .mixed: "Mix of both"
        }
    }

    private func toggle(_ number: Int) {
        if selected.contains(number) { selected.remove(number) } else { selected.insert(number) }
    }

    private func makeCards() -> [DrillCard] {
        selectedWords.map { word in
            let cardDirection: CardDirection = switch direction {
            case .toEnglish: .toEnglish
            case .fromEnglish: .fromEnglish
            case .mixed: Bool.random() ? .toEnglish : .fromEnglish
            }
            return DrillCard(word: word, direction: cardDirection)
        }
    }
}
