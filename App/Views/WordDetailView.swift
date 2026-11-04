import SwiftUI

/// Everything about one word. Teachers see the teaching tip first.
struct WordDetailView: View {
    let word: Word
    let isTeaching: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        HeadwordView(word: word)
                        Spacer()
                        SpeakButton(word: word)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.gloss).font(.title2.weight(.medium))
                        Text(word.partOfSpeech).font(.subheadline).foregroundStyle(.secondary)
                    }

                    pinButton

                    if isTeaching {
                        tipCard
                        practiceCard
                    }

                    grammar

                    if let characters = word.characters, !characters.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Characters").font(.headline)
                            ForEach(characters, id: \.self) { part in
                                HStack(spacing: 14) {
                                    Text(part.char).font(.system(size: 32, weight: .semibold))
                                    VStack(alignment: .leading) {
                                        Text(part.pinyin).font(.subheadline.weight(.medium))
                                        Text(part.meaning).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Example").font(.headline)
                        ForEach(word.examples, id: \.self) { example in
                            ExampleView(example: example, language: word.language)
                        }
                    }
                    .card()

                    if !isTeaching { tipCard }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(isTeaching ? "Teaching notes" : "Your word")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var pinButton: some View {
        let pinned = progress.data.pinnedWordID == word.id
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { progress.togglePin(word.id) }
            } label: {
                Label(pinned ? "On your Lock Screen" : "Show on Lock Screen",
                      systemImage: pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.bordered)
            .tint(pinned ? .orange : .accentColor)

            Text(pinned
                 ? "Tap again to go back to a different word each day."
                 : "Needs the Pair widget: touch and hold your Lock Screen, tap Customise, then add Pair.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(isTeaching ? "How to teach it" : "Note", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(word.tip)
        }
        .card()
    }

    @ViewBuilder
    private var practiceCard: some View {
        if let practice = GrammarNotes.practice(for: word) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Try it with them", systemImage: "person.2.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text(practice)
            }
            .card()
        }
    }

    @ViewBuilder
    private var grammar: some View {
        if let noun = word.noun {
            grammarCard(rows: [
                ("Gender", "\(noun.article) (\(genderName(noun.gender)))"),
                ("Plural", noun.plural.map { "die \($0)" } ?? "usually none"),
            ], note: GrammarNotes.pattern(for: word))
        } else if let verb = word.verb {
            let aux = verb.auxiliary == "sein" ? "ist" : "hat"
            grammarCard(rows: [
                ("He / she / it", "er \(verb.present3sg)"),
                ("Past (perfect)", "er \(aux) \(verb.participle)"),
            ])
        } else if let measure = word.measureWord {
            grammarCard(rows: [
                ("Measure word", "\(measure.word) \(measure.pinyin)"),
                ("One of them", MeasureWords.countingPhrase(for: word)?.text ?? "一\(measure.word)\(word.word)"),
            ], note: GrammarNotes.pattern(for: word))
        } else if word.countsDirectly, let phrase = MeasureWords.countingPhrase(for: word) {
            grammarCard(rows: [
                ("Measure word", "none"),
                ("Three of them", phrase.text),
            ], note: GrammarNotes.pattern(for: word))
        }
    }

    private func grammarCard(rows: [(String, String)], note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).fontWeight(.medium)
                }
            }
            if let note {
                Divider()
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func genderName(_ gender: String) -> String {
        switch gender {
        case "m": "masculine"
        case "f": "feminine"
        default: "neuter"
        }
    }
}
