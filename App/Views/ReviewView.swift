import SwiftUI

struct ReviewView: View {
    private enum Mode { case idle, due, practice }

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content

    @State private var mode: Mode = .idle
    @State private var queue: [String] = []
    @State private var revealed = false
    @State private var reviewedThisRound = 0
    @State private var quizzing = false

    var body: some View {
        NavigationStack {
            Group {
                if mode != .idle, let id = queue.first, let word = content.words[id] {
                    flashcard(word)
                } else {
                    summary
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
            .toolbar {
                if mode != .idle {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End") { endRound() }
                    }
                }
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        let due = progress.dueWordIDs()
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: due.isEmpty ? "checkmark.circle.fill" : "rectangle.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(due.isEmpty ? Color.green : Color.accentColor)

            if reviewedThisRound > 0 && due.isEmpty {
                Text("Review done").font(.title.bold())
                Text("You went through \(reviewedThisRound) cards.").foregroundStyle(.secondary)
            } else if !due.isEmpty {
                Text("\(due.count) word\(due.count == 1 ? "" : "s") to review").font(.title.bold())
                Text("A few minutes a day keeps them stuck.").foregroundStyle(.secondary)
            } else if progress.learnedCount == 0 {
                Text("Nothing to review yet").font(.title.bold())
                Text("Words appear here once you finish your first session.")
                    .foregroundStyle(.secondary)
            } else {
                Text("All caught up").font(.title.bold())
                if let next = progress.nextDueDate {
                    Text("Next review \(next.formatted(.relative(presentation: .named))).")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                if !due.isEmpty {
                    Button {
                        start(.due, with: due)
                    } label: {
                        Text("Start review").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if progress.learnedCount > 0 {
                    Button {
                        start(.practice, with: Array(progress.learnedWordIDs.shuffled().prefix(20)))
                    } label: {
                        Text("Practise anyway").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    Text("Practice doesn't change when words are next due.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            Spacer()
            quizCard
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .sheet(isPresented: $quizzing) {
            if let teaching = progress.teaching {
                QuizView(language: teaching, words: quizWords)
            }
        }
    }

    // MARK: Quiz your partner

    private var quizWords: [Word] {
        progress.partnerWordIDs(in: content).compactMap { content.words[$0] }.shuffled().prefix(20).map { $0 }
    }

    @ViewBuilder
    private var quizCard: some View {
        let count = progress.partnerWordIDs(in: content).count
        if count > 0, let teaching = progress.teaching {
            Button {
                quizzing = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiz your partner").font(.headline)
                        Text("\(count) \(teaching.name) words so far. They answer out loud, you check.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Flashcard

    private func flashcard(_ word: Word) -> some View {
        VStack(spacing: 16) {
            Text(mode == .practice ? "Practice · \(queue.count) left" : "\(queue.count) left")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 18) {
                Spacer(minLength: 0)
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
                } else {
                    Text("What does it mean?")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card(padding: 20)
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { revealed = true } }

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
        }
        .padding(16)
    }

    private func gradeButtons(for word: Word) -> some View {
        HStack(spacing: 10) {
            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                Button {
                    submit(grade, for: word)
                } label: {
                    VStack(spacing: 2) {
                        Text(grade.title).font(.headline)
                        if mode == .due, let state = progress.review(for: word.id) {
                            Text(intervalLabel(Scheduler.days(after: state, grade: grade)))
                                .font(.caption)
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

    // MARK: Actions

    private func start(_ newMode: Mode, with ids: [String]) {
        queue = ids
        revealed = false
        reviewedThisRound = 0
        mode = ids.isEmpty ? .idle : newMode
    }

    private func submit(_ grade: ReviewGrade, for word: Word) {
        if mode == .due {
            progress.record(grade, for: word.id)
        }
        reviewedThisRound += 1
        withAnimation(.snappy) {
            queue.removeFirst()
            // Forgotten words come round again at the end of this round.
            if grade == .again { queue.append(word.id) }
            revealed = false
            if queue.isEmpty { mode = .idle }
        }
    }

    private func endRound() {
        queue = []
        revealed = false
        mode = .idle
    }

    private func tint(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .good: .accentColor
        case .easy: .green
        }
    }

    private func intervalLabel(_ days: Int) -> String {
        days == 1 ? "tomorrow" : "\(days) days"
    }
}
