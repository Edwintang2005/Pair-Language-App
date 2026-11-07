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
        VStack(spacing: 16) {
            DrillProgressHeader(results: answers, total: total, position: total - queue.count + 1)
            ChoiceQuestionCard(question: question, nextTitle: queue.count > 1 ? "Next" : "See results",
                               onAnswer: { record(question, right: $0) }, onNext: { next(after: question.id) })
                .id(question.id)
        }
        .padding(16)
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
        case .tones:
            HStack(spacing: 12) {
                HeadwordView(word: word, style: .medium)
                TonePatternLabel(tones: Tones.pattern(of: word))
            }
        }
    }

    // MARK: Actions

    private func start(with ids: [String]) {
        queue = drill.questions(wordIDs: ids, content: content)
        total = queue.count
        correct = 0
        missed = []
        answers = []
        started = true
    }

    private func record(_ question: ChoiceQuestion, right: Bool) {
        withAnimation(.snappy) { answers.append(right) }
        if right { correct += 1 } else { missed.append(question) }
    }

    /// Only moves on from the question that asked, so a double tap on Next can't skip one.
    private func next(after id: UUID) {
        guard queue.first?.id == id else { return }
        withAnimation(.snappy) { _ = queue.removeFirst() }
    }
}

/// One tap-the-answer question: the word (or a play button), the options, and after answering,
/// the right answer with a note on why. Used by the drills and by the mixed Practise round.
struct ChoiceQuestionCard: View {
    let question: ChoiceQuestion
    /// "Next", or "See results" on the last question.
    let nextTitle: String
    let onAnswer: (Bool) -> Void
    let onNext: () -> Void

    @State private var picked: String?

    private var drill: ChoiceDrill { question.kind }
    private var language: Language { question.word.language }

    var body: some View {
        let word = question.word
        return VStack(spacing: 16) {
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
                    // Listening and tones are about your ear, so the meaning waits until you've answered.
                    if picked != nil || !drill.isHeard {
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
                    onNext()
                } label: {
                    Text(nextTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task(id: question.id) {
            // Listening and tones play each word as it comes up.
            if drill.isHeard { say(word) }
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
        case .listening, .tones:
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
            if drill == .tones {
                Button {
                    say(word, slow: true)
                } label: {
                    Label("Slow", systemImage: "tortoise.fill").font(.headline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            } else {
                Text("Tap to hear it again").font(.subheadline).foregroundStyle(.secondary)
            }
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
        case .listening, .tones:
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
        if question.isCorrect(picked) {
            return drill == .tones
                ? "Right. It's written \(label(question.answer))"
                : "Also right. \(label(question.answer)) is the usual one."
        }
        return drill == .listening ? "It means \"\(question.answer)\"" : "It's \(label(question.answer))"
    }

    private func explanation(for word: Word) -> String? {
        switch drill {
        case .grammar: grammarExplanation(for: word)
        case .plurals: Plurals.explanation(for: word)
        case .pastTense: PastTense.explanation(for: word)
        case .listening: nil
        case .tones: Tones.explanation(for: word)
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
            Group {
                if drill == .tones {
                    TonePatternLabel(tones: Tones.tones(fromLabel: option))
                } else {
                    Text(label(option))
                        .font(font)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
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
        if drill == .tones { return Tones.tones(fromLabel: option).map(String.init).joined(separator: " + ") }
        return option == GrammarDrill.noMeasureWord ? "No measure word" : option
    }

    private func tint(for option: String, in question: ChoiceQuestion) -> Color {
        guard drill == .grammar, question.word.language == .german else { return .accentColor }
        switch option {
        case "der": return .gender("m")
        case "die": return .gender("f")
        default: return .gender("n")
        }
    }

    private func answer(_ question: ChoiceQuestion, with option: String) {
        // A second tap can land before the buttons are disabled: count the first only.
        guard picked == nil else { return }
        withAnimation(.snappy) { picked = option }
        onAnswer(question.isCorrect(option))
    }

    private func say(_ word: Word, slow: Bool = false) {
        Speaker.shared.say(word.headword, in: word.language, slow: slow)
    }
}

/// "3 / 10" and the coloured segments above a marked round.
struct DrillProgressHeader: View {
    /// Right or wrong for each question answered so far.
    let results: [Bool]
    let total: Int
    /// The question on screen, from 1.
    let position: Int

    var body: some View {
        HStack(spacing: 12) {
            // Once the current question is answered, the highlight doesn't run ahead to the next.
            RoundProgress(results: results, total: total, showsCurrent: results.count < position)
            Text("\(min(position, total)) / \(total)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

extension ChoiceDrill {
    /// Drills you answer by ear: the word is played, not shown.
    var isHeard: Bool { self == .listening || self == .tones }
}

/// A tone pattern drawn as pitch shapes with the numbers underneath: ⌐ ↗ for 1 + 2.
struct TonePatternLabel: View {
    let tones: [Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(tones.enumerated()), id: \.offset) { _, tone in
                VStack(spacing: 3) {
                    ToneContour(tone: tone)
                        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 26, height: 18)
                    Text(tone == 0 ? "·" : "\(tone)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(tones.map(Tones.name(of:)).joined(separator: ", then "))
    }
}

/// The pitch of one tone on the usual five-level scale (5 high, 1 low):
/// 1st 55, 2nd 35, 3rd 214, 4th 51, neutral a short dot.
nonisolated struct ToneContour: Shape {
    let tone: Int

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ level: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + (5 - level) / 4 * rect.height)
        }
        var path = Path()
        switch tone {
        case 1:
            path.move(to: point(0, 5)); path.addLine(to: point(1, 5))
        case 2:
            path.move(to: point(0, 3)); path.addLine(to: point(1, 5))
        case 3:
            path.move(to: point(0, 2))
            path.addQuadCurve(to: point(1, 4), control: point(0.4, 0))
        case 4:
            path.move(to: point(0, 5)); path.addLine(to: point(1, 1))
        default:
            path.move(to: point(0.4, 2.5)); path.addLine(to: point(0.6, 2.5))
        }
        return path
    }
}
