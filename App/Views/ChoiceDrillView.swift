import SwiftUI

/// A quick tap-the-answer round: der/die/das or measure words, plurals, the past tense, or listening.
/// Marked by the app, and never touches the review schedule.
struct ChoiceDrillView: View {
    let drill: ChoiceDrill
    let language: Language
    let wordIDs: [String]

    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [ChoiceQuestion] = []
    @State private var total = 0
    @State private var picked: String?
    @State private var correct = 0
    @State private var missed: [ChoiceQuestion] = []
    @State private var answers: [Bool] = []
    @State private var started = false

    var body: some View {
        NavigationStack {
            // A ZStack, not a Group: modifiers on an empty Group (the first frame, before the
            // questions are dealt) are dropped.
            ZStack {
                if let question = queue.first {
                    questionView(question)
                } else if started {
                    results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(drill.title(for: language))
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

    private func questionView(_ question: ChoiceQuestion) -> some View {
        let word = question.word
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                RoundProgress(results: answers, total: total, showsCurrent: picked == nil)
                Text("\(total - queue.count + 1) / \(total)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Centred when it fits, scrollable when the explanation doesn't.
            GeometryReader { geo in
            ScrollView {
                VStack(spacing: 14) {
                    Text(drill.prompt(for: language))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if picked == nil {
                        unansweredHeadline(word)
                    } else {
                        answerHeadline(question)
                    }
                    if picked != nil || drill != .listening {
                        Text(word.gloss).font(.title3).foregroundStyle(.secondary)
                    }

                    if let picked {
                        feedback(question, picked: picked)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))

            // The options stay on screen after answering, showing your pick and the right answer.
            optionButtons(question)
            if picked != nil {
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
        .task(id: question.id) {
            // Listening plays each word as it comes up.
            if drill == .listening { say(word) }
        }
    }

    @ViewBuilder
    private func unansweredHeadline(_ word: Word) -> some View {
        switch drill {
        case .grammar:
            // The bare word: no coloured article, no measure word.
            Text(word.word)
                .font(.system(size: word.language == .chinese ? 72 : 44, weight: .bold))
            if let pinyin = word.pinyin {
                Text(pinyin).font(.title3).foregroundStyle(.secondary)
            }
        case .plurals:
            HeadwordView(word: word, style: .flashcard)
            Text("die …").font(.title).foregroundStyle(.secondary)
        case .pastTense:
            Text(word.word).font(.system(size: 44, weight: .bold))
            Text("er …").font(.title).foregroundStyle(.secondary)
        case .listening:
            Button {
                say(word)
            } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 44))
                    .frame(width: 112, height: 112)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("Play the word again")
            Text("Tap to hear it again").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func answerHeadline(_ question: ChoiceQuestion) -> some View {
        let word = question.word
        switch drill {
        case .grammar:
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
        case .plurals:
            HeadwordView(word: word, style: .medium)
            Text("die \(question.answer)").font(.system(size: 40, weight: .bold))
            SpeakButton(text: "die \(question.answer)", language: .german, size: .title2)
        case .pastTense:
            Text(word.word).font(.title3.weight(.semibold))
            Text("er \(question.answer)").font(.system(size: 36, weight: .bold))
            SpeakButton(text: "er \(question.answer)", language: .german, size: .title2)
        case .listening:
            HeadwordView(word: word, style: .flashcard)
            SpeakButton(word: word, size: .title2)
        }
    }

    private func feedback(_ question: ChoiceQuestion, picked: String) -> some View {
        let right = question.isCorrect(picked)
        return VStack(spacing: 10) {
            Label(verdict(question, picked: picked),
                  systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(right ? .green : .red)

            if drill == .listening, let example = question.word.examples.first {
                ExampleView(example: example, language: question.word.language)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            } else if let note = explanation(for: question.word) {
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

    private func verdict(_ question: ChoiceQuestion, picked: String) -> String {
        if picked == question.answer { return "Right" }
        if question.isCorrect(picked) { return "Also right. \(label(question.answer)) is the usual one." }
        return drill == .listening ? "It means \"\(question.answer)\"" : "It's \(label(question.answer))"
    }

    private func explanation(for word: Word) -> String? {
        switch drill {
        case .grammar: grammarExplanation(for: word)
        case .plurals: Plurals.explanation(for: word)
        case .pastTense: PastTense.explanation(for: word)
        case .listening: nil
        }
    }

    private func grammarExplanation(for word: Word) -> String? {
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

    // MARK: Options

    @ViewBuilder
    private func optionButtons(_ question: ChoiceQuestion) -> some View {
        if drill == .grammar {
            let words = question.options.filter { $0 != GrammarDrill.noMeasureWord }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: words.count)
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(words, id: \.self) { option in
                        optionButton(option, in: question, font: .title2.weight(.semibold))
                    }
                }
                if question.options.contains(GrammarDrill.noMeasureWord) {
                    optionButton(GrammarDrill.noMeasureWord, in: question, font: .headline)
                }
            }
        } else {
            // Longer answers: two by two.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(question.options, id: \.self) { option in
                    optionButton(option, in: question,
                                 font: drill == .plurals ? .title3.weight(.semibold) : .headline)
                }
            }
        }
    }

    private func optionButton(_ option: String, in question: ChoiceQuestion, font: Font) -> some View {
        let outline = outlineColor(for: option, in: question)
        return Button {
            answer(question, with: option)
        } label: {
            Text(label(option))
                .font(font)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(outline ?? tint(for: option, in: question))
        .overlay {
            if let outline { Capsule().strokeBorder(outline, lineWidth: 2.5) }
        }
        .opacity(picked != nil && outline == nil ? 0.35 : 1)
        .allowsHitTesting(picked == nil)
        .accessibilityAddTraits(picked == option ? .isSelected : [])
    }

    /// After answering: green for the right answer (and your pick, if it's also right), red for a wrong pick.
    private func outlineColor(for option: String, in question: ChoiceQuestion) -> Color? {
        guard let picked else { return nil }
        if option == question.answer || (option == picked && question.isCorrect(option)) { return .green }
        if option == picked { return .red }
        return nil
    }

    private func label(_ option: String) -> String {
        option == GrammarDrill.noMeasureWord ? "No measure word" : option
    }

    private func tint(for option: String, in question: ChoiceQuestion) -> Color {
        guard drill == .grammar, question.word.language == .german else { return .accentColor }
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
                        ForEach(missed) { question in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    missedHeadline(question)
                                    Text(question.word.gloss).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .card(padding: 14)
                        }
                    }

                    Button {
                        start(with: missed.map(\.word.id))
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

    @ViewBuilder
    private func missedHeadline(_ question: ChoiceQuestion) -> some View {
        let word = question.word
        switch drill {
        case .grammar:
            if word.noun != nil {
                HeadwordView(word: word, style: .medium)
            } else if let phrase = MeasureWords.countingPhrase(for: word) {
                Text(phrase.text).font(.system(size: 26, weight: .semibold))
                Text(phrase.pinyin).font(.subheadline).foregroundStyle(.secondary)
            }
        case .plurals:
            Text("\(word.headword) → die \(question.answer)").font(.title3.weight(.semibold))
        case .pastTense:
            Text("\(word.word) → er \(question.answer)").font(.title3.weight(.semibold))
        case .listening:
            HeadwordView(word: word, style: .medium)
        }
    }

    // MARK: Actions

    private func start(with ids: [String]) {
        queue = drill.questions(wordIDs: ids, content: content)
        total = queue.count
        correct = 0
        missed = []
        answers = []
        picked = nil
        started = true
    }

    private func answer(_ question: ChoiceQuestion, with option: String) {
        withAnimation(.snappy) {
            picked = option
            answers.append(question.isCorrect(option))
        }
        if question.isCorrect(option) {
            correct += 1
        } else {
            missed.append(question)
        }
    }

    private func next() {
        withAnimation(.snappy) {
            queue.removeFirst()
            picked = nil
        }
    }

    private func say(_ word: Word) {
        Speaker.shared.say(word.headword, in: word.language)
    }
}
