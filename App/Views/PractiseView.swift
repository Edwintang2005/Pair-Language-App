import SwiftUI

/// The mixed Practise round: tones, listening, sentences and speaking in one go.
/// Marked by the app (except speaking), and never touches the review schedule.
struct PractiseView: View {
    let language: Language

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [PractiseItem] = []
    @State private var total = 0
    @State private var answers: [Bool] = []
    @State private var marked = 0
    @State private var correct = 0
    @State private var spoken = 0
    @State private var started = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let item = queue.first {
                    VStack(spacing: 16) {
                        DrillProgressHeader(results: answers, total: total, position: total - queue.count + 1)
                        card(for: item)
                            .id(item.id)
                    }
                    .padding(16)
                } else if started {
                    finished
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Practise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if !started { start() }
        }
        .onDisappear { AudioSession.usePlayback() }
    }

    @ViewBuilder
    private func card(for item: PractiseItem) -> some View {
        let nextTitle = queue.count > 1 ? "Next" : "See how you did"
        switch item {
        case .choice(let question):
            ChoiceQuestionCard(question: question, nextTitle: nextTitle, onAnswer: record,
                               onNext: { next(after: item.id) })
        case .sentence(let puzzle):
            SentencePuzzleCard(puzzle: puzzle, listenOnly: true, nextTitle: nextTitle, onCheck: record,
                               onNext: { next(after: item.id) })
        case .speaking(let speaking):
            SpeakingCard(item: speaking, nextTitle: nextTitle) {
                guard queue.first?.id == item.id else { return }
                spoken += 1
                // Not marked, but it still fills its segment.
                withAnimation(.snappy) { answers.append(true) }
                next(after: item.id)
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: correct == marked ? "star.fill" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(correct == marked ? Color.yellow : Color.green)
            Text("\(correct) of \(marked) right").font(.largeTitle.bold())
            if spoken > 0 {
                Text("And you said \(spoken) sentence\(spoken == 1 ? "" : "s") out loud.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                start()
            } label: {
                Text("Another round").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button("Done") { dismiss() }
                .padding(.top, 4)
        }
        .padding(16)
    }

    private func start() {
        queue = PractiseRound.items(language: language, knownIDs: progress.knownWordIDs,
                                    box: { progress.review(for: $0)?.box }, content: content)
        total = queue.count
        answers = []
        marked = queue.filter(\.isMarked).count
        correct = 0
        spoken = 0
        started = true
    }

    private func record(_ right: Bool) {
        withAnimation(.snappy) { answers.append(right) }
        if right { correct += 1 }
    }

    /// Only moves on from the step that asked, so a double tap on Next can't skip one.
    private func next(after id: UUID) {
        guard queue.first?.id == id else { return }
        withAnimation(.snappy) { _ = queue.removeFirst() }
    }
}
