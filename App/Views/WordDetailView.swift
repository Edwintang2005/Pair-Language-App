import SwiftUI

/// Everything about one word. Teachers see the teaching tip first.
struct WordDetailView: View {
    let word: Word
    let isTeaching: Bool

    @Environment(\.dismiss) private var dismiss

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

                    if isTeaching { tipCard }

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
    private var grammar: some View {
        if let noun = word.noun {
            grammarCard(rows: [
                ("Gender", "\(noun.article) (\(genderName(noun.gender)))"),
                ("Plural", noun.plural.map { "die \($0)" } ?? "usually none"),
            ])
        } else if let verb = word.verb {
            let aux = verb.auxiliary == "sein" ? "ist" : "hat"
            grammarCard(rows: [
                ("He / she / it", "er \(verb.present3sg)"),
                ("Past (perfect)", "er \(aux) \(verb.participle)"),
            ])
        } else if let measure = word.measureWord {
            grammarCard(rows: [
                ("Measure word", "\(measure.word) \(measure.pinyin)"),
                ("e.g.", "一\(measure.word)\(word.word)"),
            ])
        }
    }

    private func grammarCard(rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).fontWeight(.medium)
                }
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
