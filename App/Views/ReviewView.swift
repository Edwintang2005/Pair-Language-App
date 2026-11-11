import SwiftUI

struct ReviewView: View {
    /// One review round, shown full screen.
    private struct Round: Identifiable {
        let id = UUID()
        let wordIDs: [String]
    }

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content

    @State private var round: Round?
    @State private var quizzing = false
    @State private var testingSelf = false
    @State private var choiceDrill: ChoiceDrill?
    @State private var buildingSentences = false
    @State private var speaking = false
    @State private var practising = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if progress.learnedCount > 0 {
                        strengthSummary
                    }
                    reviewCard
                    practice
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
        }
        .fullScreenCover(item: $round) { round in
            ReviewRoundView(wordIDs: round.wordIDs)
        }
        .sheet(isPresented: $quizzing) {
            NavigationStack {
                DrillView(title: "Quiz your partner", kind: .partnerQuiz, cards: quizCards)
            }
        }
        .sheet(item: $choiceDrill) { drill in
            if let learning = progress.learning {
                ChoiceDrillView(drill: drill, language: learning, wordIDs: progress.knownWordIDs)
            }
        }
        .fullScreenCover(isPresented: $practising) {
            if let learning = progress.learning {
                PractiseView(language: learning)
            }
        }
        .sheet(isPresented: $speaking) {
            if let learning = progress.learning {
                SpeakingDrillView(language: learning, wordIDs: progress.knownWordIDs)
            }
        }
        .sheet(isPresented: $buildingSentences) {
            if let learning = progress.learning {
                SentenceDrillView(language: learning, wordIDs: progress.knownWordIDs)
            }
        }
        .sheet(isPresented: $testingSelf) {
            if let learning = progress.learning {
                PracticeSetupView(learning: learning)
            }
        }
    }

    // MARK: How your words are doing

    private var strengthSummary: some View {
        let counts = progress.strengthCounts()
        let levels: [(Strength, Color)] = [(.new, .orange), (.learning, .blue), (.strong, .green)]
        let total = max(progress.learnedCount, 1)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(levels, id: \.0) { level, color in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(color)
                        Text("\(counts[level] ?? 0)")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12)
                }
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(levels, id: \.0) { level, color in
                        let count = counts[level] ?? 0
                        if count > 0 {
                            Capsule()
                                .fill(color)
                                .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(total) - 2))
                        }
                    }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Today's review

    private var reviewCard: some View {
        let due = progress.dueWordIDs()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(dueCount: due.count)).font(.title3.weight(.semibold))
                    Text(detail(dueCount: due.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: due.isEmpty ? "checkmark.circle.fill" : "rectangle.on.rectangle.angled")
                    .font(.title)
                    .foregroundStyle(due.isEmpty ? Color.green : Color.accentColor)
            }
            if !due.isEmpty {
                Button {
                    round = Round(wordIDs: due)
                } label: {
                    Text("Start review").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .card(padding: 16)
    }

    private func headline(dueCount: Int) -> String {
        if dueCount > 0 { return "\(dueCount) word\(dueCount == 1 ? "" : "s") due" }
        return progress.learnedCount == 0 ? "Nothing to review yet" : "All caught up"
    }

    private func detail(dueCount: Int) -> String {
        if dueCount > 0 {
            // Roughly 15 seconds a card.
            let minutes = max(1, Int((Double(dueCount) * 15 / 60).rounded()))
            return "About \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        if progress.learnedCount == 0 {
            return "Words appear here once you finish your first session."
        }
        guard let next = progress.upcomingReview() else { return "" }
        let when = Calendar.current.isDateInTomorrow(next.date)
            ? "tomorrow"
            : next.date.formatted(.relative(presentation: .named))
        return "Next review \(when): \(next.count) word\(next.count == 1 ? "" : "s")"
    }

    // MARK: Practice

    @ViewBuilder
    private var practice: some View {
        let tiles = practiceTiles
        if !tiles.isEmpty {
            Text("Practise")
                .font(.title3.bold())
                .padding(.top, 4)
            if let learning = progress.learning,
               progress.knownWordIDs.count >= PractiseRound.minimumWords {
                practiseCard(for: learning)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(tiles) { tile in
                    PracticeTile(tile: tile)
                }
            }
        }
    }

    /// The one-tap mixed round, above the individual drills.
    private func practiseCard(for learning: Language) -> some View {
        Button {
            practising = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Practise · 5 minutes").font(.headline).foregroundStyle(.primary)
                    Text(learning == .chinese
                         ? "Tones, listening, sentences and speaking"
                         : "Grammar, listening, sentences and speaking")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var practiceTiles: [PracticeTile.Model] {
        guard let learning = progress.learning else { return [] }
        var tiles: [PracticeTile.Model] = []
        if progress.learnedCount > 0 {
            tiles.append(.init(id: "self", icon: .symbol("rectangle.stack.fill"), title: "Test yourself",
                               subtitle: "Flashcards by session") { testingSelf = true })
        }
        let known = progress.knownWordIDs
        func addDrill(_ drill: ChoiceDrill, minimum: Int = 1) {
            let count = drill.eligibleCount(in: known, content: content)
            guard count >= minimum else { return }
            tiles.append(.init(id: drill.id, icon: icon(for: drill, learning: learning), title: drill.title(for: learning),
                               subtitle: subtitle(for: drill, count: count)) { choiceDrill = drill })
        }
        for drill in ChoiceDrill.drills(for: learning) where drill != .listening {
            addDrill(drill)
        }
        let sentences = SentenceBuilder.eligibleCount(in: known, content: content)
        if sentences > 0 {
            tiles.append(.init(id: "sentences", icon: .symbol("text.word.spacing"), title: "Build the sentence",
                               subtitle: "\(sentences) sentence\(sentences == 1 ? "" : "s")") { buildingSentences = true })
        }
        // Listening needs a few words to choose between.
        addDrill(.listening, minimum: 4)
        let spoken = SpeakingItem.eligibleCount(in: known, content: content)
        if spoken > 0 {
            tiles.append(.init(id: "speaking", icon: .symbol("waveform.and.mic"), title: "Speaking",
                               subtitle: "Copy what you hear") { speaking = true })
        }
        let partnerCount = progress.partnerWordIDs(in: content).count
        if partnerCount > 0 {
            tiles.append(.init(id: "quiz", icon: .symbol("person.2.fill"), title: "Quiz your partner",
                               subtitle: "\(partnerCount) \(learning.other.name) words") { quizzing = true })
        }
        return tiles
    }

    private func icon(for drill: ChoiceDrill, learning: Language) -> PracticeTile.Icon {
        switch drill {
        case .grammar: learning == .german ? .articles : .text("个张条")
        case .plurals: .text("-e -er -n")
        case .pastTense: .text("hat · ist")
        case .listening: .symbol("ear")
        case .tones: .text("ā á ǎ à")
        }
    }

    private func subtitle(for drill: ChoiceDrill, count: Int) -> String {
        let plural = count == 1 ? "" : "s"
        switch drill {
        case .grammar, .plurals: return "\(count) noun\(plural)"
        case .pastTense: return "\(count) verb\(plural)"
        case .listening, .tones: return "\(count) word\(plural)"
        }
    }

    private var quizCards: [DrillCard] {
        progress.partnerWordIDs(in: content)
            .compactMap { content.words[$0] }
            .shuffled()
            .prefix(20)
            .map { DrillCard(word: $0, direction: .fromEnglish) }
    }
}

/// One square-ish practice option on the Review tab.
struct PracticeTile: View {
    enum Icon {
        case symbol(String)
        case text(String)
        /// "der die das" in the gender colours.
        case articles
    }

    struct Model: Identifiable {
        let id: String
        let icon: Icon
        let title: String
        let subtitle: String
        let action: () -> Void
    }

    let tile: Model

    var body: some View {
        Button(action: tile.action) {
            VStack(alignment: .leading, spacing: 6) {
                icon.frame(height: 26, alignment: .leading)
                Spacer(minLength: 0)
                Text(tile.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(tile.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        switch tile.icon {
        case .symbol(let name):
            Image(systemName: name).font(.title2).foregroundStyle(.tint)
        case .text(let text):
            Text(text).font(.title3.weight(.semibold)).foregroundStyle(.tint)
        case .articles:
            HStack(spacing: 5) {
                Text("der").foregroundStyle(Color.gender("m"))
                Text("die").foregroundStyle(Color.gender("f"))
                Text("das").foregroundStyle(Color.gender("n"))
            }
            .font(.headline)
        }
    }
}

/// A full-screen review round: one card at a time, nothing else on screen.
struct ReviewRoundView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [String]
    @State private var revealed = false
    @State private var reviewed = 0

    init(wordIDs: [String]) {
        _queue = State(initialValue: wordIDs)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
                .accessibilityLabel("End review")

                RoundProgress(done: reviewed, total: reviewed + queue.count)
                Text(queue.isEmpty ? "Done" : "\(queue.count) left")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
            }

            if let id = queue.first, let word = content.words[id] {
                card(word)
                if revealed {
                    gradeButtons(for: word)
                } else {
                    Button {
                        withAnimation(.snappy) { revealed = true }
                    } label: {
                        Text("Show answer").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                finished
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
        .onDisappear { Speaker.shared.stop() }
    }

    private func card(_ word: Word) -> some View {
        // Centred when it fits, scrollable when a long example doesn't.
        GeometryReader { geo in
        ScrollView {
            VStack(spacing: 16) {
                if !revealed {
                    Text("What does it mean?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                // Chinese pinyin stays hidden until the reveal, so you practise reading the characters.
                HeadwordView(word: word, style: .flashcard, showsPinyin: revealed)
                SpeakButton(word: word, size: .title2)
                if revealed {
                    Divider()
                    VStack(spacing: 6) {
                        Text(word.gloss).font(.title2.weight(.semibold))
                        if let grammar = word.grammarLine {
                            Text(grammar).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let example = word.examples.first {
                        ExampleView(example: example, language: word.language)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: geo.size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { revealed = true } }
    }

    private func gradeButtons(for word: Word) -> some View {
        HStack(spacing: 10) {
            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                Button {
                    submit(grade, for: word)
                } label: {
                    VStack(spacing: 2) {
                        Text(grade.title).font(.headline)
                        if let state = progress.review(for: word.id) {
                            let days = Scheduler.days(after: state, grade: grade)
                            Text(days == 1 ? "tomorrow" : "\(days) days").font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: grade))
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Review done").font(.title.bold())
            Text("You went through \(reviewed) card\(reviewed == 1 ? "" : "s").")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func submit(_ grade: ReviewGrade, for word: Word) {
        // Two grade buttons tapped at once: only the first counts (a second would grade the next
        // card unseen, or crash on the last one).
        guard revealed, queue.first == word.id else { return }
        progress.record(grade, for: word.id)
        withAnimation(.snappy) {
            reviewed += 1
            queue.removeFirst()
            // Forgotten words come round again at the end of this round.
            if grade == .again { queue.append(word.id) }
            revealed = false
        }
    }

    private func tint(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .good: .accentColor
        case .easy: .green
        }
    }
}
