import SwiftUI

/// A quick tap-the-answer round: der/die/das for German nouns, the measure word for Chinese ones.
/// Marked by the app, and never touches the review schedule.
struct GrammarDrillView: View {
    let language: Language
    let wordIDs: [String]

    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [GrammarQuestion] = []
    @State private var total = 0
    @State private var picked: String?
    @State private var correct = 0
    @State private var missed: [Word] = []
    @State private var started = false

    var body: some View {
        NavigationStack {
            Group {
                if let question = queue.first {
                    questionView(question)
                } else if started {
                    results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(GrammarDrill.title(for: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if !started { start(with: wordIDs) }
        }
    }

    // MARK: Question

    private func questionView(_ question: GrammarQuestion) -> some View {
        let word = question.word
        return VStack(spacing: 16) {
            Text("\(total - queue.count + 1) of \(total)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 14) {
                    Text(prompt)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if picked == nil {
                        // The bare word: no coloured article, no measure word.
                        Text(word.word)
                            .font(.system(size: word.language == .chinese ? 72 : 44, weight: .bold))
                        if let pinyin = word.pinyin {
                            Text(pinyin).font(.title3).foregroundStyle(.secondary)
                        }
                    } else {
                        answerHeadline(word)
                    }
                    Text(word.gloss).font(.title3).foregroundStyle(.secondary)

                    if let picked {
                        feedback(question, picked: picked)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .card(padding: 20)

            if picked == nil {
                optionButtons(question)
            } else {
                Button {
                    next()
                } label: {
                    Text(queue.count > 1 ? "Next" : "See results")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var prompt: String {
        language == .german ? "der, die or das?" : "Which measure word?"
    }

    @ViewBuilder
    private func answerHeadline(_ word: Word) -> some View {
        if word.noun != nil {
            HeadwordView(word: word, style: .flashcard)
            SpeakButton(word: word, size: .title2)
        } else if let phrase = MeasureWords.countingPhrase(for: word) {
            VStack(spacing: 2) {
                Text(phrase.text).font(.system(size: 56, weight: .bold))
                Text(phrase.pinyin).font(.title3).foregroundStyle(.secondary)
            }
            SpeakButton(text: phrase.text, language: .chinese, size: .title2)
        }
    }

    private func feedback(_ question: GrammarQuestion, picked: String) -> some View {
        let right = question.isCorrect(picked)
        return VStack(spacing: 10) {
            Label(verdict(question, picked: picked),
                  systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(right ? .green : .red)

            if let note = explanation(for: question.word) {
                Text(note)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
            }
        }
        .padding(.top, 6)
    }

    private func verdict(_ question: GrammarQuestion, picked: String) -> String {
        if picked == question.answer { return "Right" }
        if question.isCorrect(picked) { return "Also right. \(label(question.answer)) is the usual one." }
        return "It's \(label(question.answer))"
    }

    private func explanation(for word: Word) -> String? {
        if word.noun != nil { return GenderHints.hint(for: word) }
        if word.countsDirectly {
            return "\(word.word) takes no measure word: the number goes straight in front."
        }
        guard let measure = word.measureWord else { return nil }
        var lines: [String] = []
        if let use = MeasureWords.uses[measure.word] {
            lines.append("\(measure.word) \(measure.pinyin): \(use).")
        }
        if let also = measure.also, !also.isEmpty {
            lines.append("You can also say " + also.map { "一\($0)\(word.word)" }.joined(separator: " or ") + ".")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private func optionButtons(_ question: GrammarQuestion) -> some View {
        let words = question.options.filter { $0 != GrammarDrill.noMeasureWord }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: words.count)
        return VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(words, id: \.self) { option in
                    optionButton(option, in: question, font: .title2.weight(.semibold))
                }
            }
            if question.options.contains(GrammarDrill.noMeasureWord) {
                optionButton(GrammarDrill.noMeasureWord, in: question, font: .headline)
            }
        }
    }

    private func optionButton(_ option: String, in question: GrammarQuestion, font: Font) -> some View {
        Button {
            answer(question, with: option)
        } label: {
            Text(label(option))
                .font(font)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(tint(for: option, in: question))
    }

    private func label(_ option: String) -> String {
        option == GrammarDrill.noMeasureWord ? "No measure word" : option
    }

    private func tint(for option: String, in question: GrammarQuestion) -> Color {
        guard question.word.language == .german else { return .accentColor }
        switch option {
        case "der": return .gender("m")
        case "die": return .gender("f")
        default: return .gender("n")
        }
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: missed.isEmpty ? "star.fill" : "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(missed.isEmpty ? Color.yellow : Color.green)
                    .padding(.top, 32)
                Text("\(correct) of \(total)").font(.largeTitle.bold())
                Text(missed.isEmpty ? "Perfect. You knew them all." : "Worth another look:")
                    .foregroundStyle(.secondary)

                if !missed.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(missed) { word in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    if word.noun != nil {
                                        HeadwordView(word: word, style: .medium)
                                    } else if let phrase = MeasureWords.countingPhrase(for: word) {
                                        Text(phrase.text).font(.system(size: 26, weight: .semibold))
                                        Text(phrase.pinyin).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Text(word.gloss).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .card(padding: 14)
                        }
                    }

                    Button {
                        start(with: missed.map(\.id))
                    } label: {
                        Text("Try the missed ones again").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Done") { dismiss() }
                    .padding(.top, 4)
            }
            .padding(16)
        }
    }

    // MARK: Actions

    private func start(with ids: [String]) {
        queue = GrammarDrill.questions(wordIDs: ids, content: content)
        total = queue.count
        correct = 0
        missed = []
        picked = nil
        started = true
    }

    private func answer(_ question: GrammarQuestion, with option: String) {
        withAnimation(.snappy) { picked = option }
        if question.isCorrect(option) {
            correct += 1
        } else {
            missed.append(question.word)
        }
    }

    private func next() {
        withAnimation(.snappy) {
            queue.removeFirst()
            picked = nil
        }
    }
}
