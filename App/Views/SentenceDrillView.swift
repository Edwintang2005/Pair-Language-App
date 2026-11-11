import SwiftUI

/// "Build the sentence": an example sentence, shuffled into tiles, to tap back into order.
/// In Listen mode you only hear it: no English, no pinyin. Marked by the app, and never touches
/// the review schedule.
struct SentenceDrillView: View {
    let language: Language
    let wordIDs: [String]

    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.sentenceDrillListens) private var listenOnly = false
    @State private var queue: [SentencePuzzle] = []
    @State private var total = 0
    @State private var correct = 0
    @State private var missed: [SentencePuzzle] = []
    @State private var answers: [Bool] = []
    @State private var started = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let puzzle = queue.first {
                    VStack(spacing: 16) {
                        Picker("Mode", selection: $listenOnly) {
                            Text("Read").tag(false)
                            Text("Listen").tag(true)
                        }
                        .pickerStyle(.segmented)
                        DrillProgressHeader(results: answers, total: total, position: total - queue.count + 1)
                        SentencePuzzleCard(puzzle: puzzle, listenOnly: listenOnly,
                                           nextTitle: queue.count > 1 ? "Next" : "See results",
                                           onCheck: { record(puzzle, right: $0) }, onNext: { next(after: puzzle.id) })
                            .id(puzzle.id)
                    }
                    .padding(16)
                } else if started {
                    results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Build the sentence")
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
        .onDisappear { Speaker.shared.stop() }
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
                Text(missed.isEmpty ? "Perfect. Every sentence in order." : "Worth another look:")
                    .foregroundStyle(.secondary)

                if !missed.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(missed) { puzzle in
                            ExampleView(example: puzzle.example, language: puzzle.word.language)
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

    // MARK: Actions

    private func start(with ids: [String]) {
        queue = SentenceBuilder.puzzles(wordIDs: ids, content: content)
        total = queue.count
        correct = 0
        missed = []
        answers = []
        started = true
    }

    private func record(_ puzzle: SentencePuzzle, right: Bool) {
        withAnimation(.snappy) { answers.append(right) }
        if right { correct += 1 } else { missed.append(puzzle) }
    }

    private func next(after id: UUID) {
        guard queue.first?.id == id else { return }
        withAnimation(.snappy) { _ = queue.removeFirst() }
    }
}

/// One sentence to build: the prompt (English, or a play button in Listen mode), the answer area,
/// the shuffled tiles, and Check / Next. Used by the drill and by the mixed Practise round.
struct SentencePuzzleCard: View {
    let puzzle: SentencePuzzle
    /// Hear it instead of reading the English, and no pinyin on the tiles.
    let listenOnly: Bool
    let nextTitle: String
    let onCheck: (Bool) -> Void
    let onNext: () -> Void

    /// The tiles placed so far, in order.
    @State private var placed: [SentenceTile] = []
    @State private var checked = false

    private var language: Language { puzzle.word.language }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        prompt
                        answerArea
                        if checked {
                            feedback
                        }
                    }
                    .card(padding: 20)

                    if !checked {
                        bank
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            actionButton
        }
        .task(id: listenOnly) {
            if listenOnly && !checked { say() }
        }
    }

    @ViewBuilder
    private var prompt: some View {
        if listenOnly {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listen, then put it in order")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if checked {
                        Text(puzzle.example.english).font(.title3.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
                Button {
                    say(slow: true)
                } label: {
                    Image(systemName: "tortoise.fill")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Play it slowly")
                Button {
                    say()
                } label: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Play the sentence again")
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Put it in order")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(puzzle.example.english)
                    .font(.title3.weight(.semibold))
            }
        }
    }

    /// Where the sentence is built. Tap a tile to send it back.
    private var answerArea: some View {
        let right = checked && puzzle.isCorrect(placed)
        let outline: Color = checked ? (right ? .green : .red) : Color(.separator)
        return FlowLayout(spacing: 8, lineSpacing: 10) {
            ForEach(placed) { tile in
                Button {
                    withAnimation(.snappy) { placed.removeAll { $0.id == tile.id } }
                } label: {
                    TileLabel(tile: tile, showsPinyin: !listenOnly || checked)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!checked)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .overlay(alignment: .leading) {
            if placed.isEmpty {
                Text("Tap the words below")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(outline, style: StrokeStyle(lineWidth: checked ? 2.5 : 1.5, dash: checked ? [] : [6, 4]))
        }
    }

    /// The shuffled tiles. A placed tile leaves a gap, so nothing jumps around.
    private var bank: some View {
        FlowLayout(spacing: 10, lineSpacing: 12, centred: true) {
            ForEach(puzzle.shuffled) { tile in
                let used = placed.contains { $0.id == tile.id }
                Button {
                    guard !placed.contains(where: { $0.id == tile.id }) else { return }
                    withAnimation(.snappy) { placed.append(tile) }
                } label: {
                    TileLabel(tile: tile, showsPinyin: !listenOnly)
                }
                .buttonStyle(.plain)
                .opacity(used ? 0.2 : 1)
                .disabled(used)
                .accessibilityHidden(used)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var feedback: some View {
        let right = puzzle.isCorrect(placed)
        return VStack(alignment: .leading, spacing: 10) {
            Label(right ? "Right" : "Not quite. Here's the sentence:",
                  systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(right ? .green : .red)
            ExampleView(example: puzzle.example, language: language)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            HStack(spacing: 6) {
                Text("For")
                    .foregroundStyle(.secondary)
                HeadwordView(word: puzzle.word, style: .medium, showsPinyin: false)
                Text("· \(puzzle.word.shortGloss)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if checked {
            Button {
                onNext()
            } label: {
                Text(nextTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                check()
            } label: {
                Text("Check").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(placed.count < puzzle.tiles.count)
        }
    }

    private func check() {
        guard !checked else { return }
        let right = puzzle.isCorrect(placed)
        withAnimation(.snappy) { checked = true }
        onCheck(right)
        say()
    }

    private func say(slow: Bool = false) {
        Speaker.shared.say(puzzle.example.text, in: language, slow: slow)
    }
}

/// One word tile: German as it is, Chinese with its pinyin underneath.
private struct TileLabel: View {
    let tile: SentenceTile
    /// Off in "Listen" mode, where you go by sound.
    var showsPinyin = true

    var body: some View {
        VStack(spacing: 1) {
            Text(tile.text)
                .font(tile.pinyin == nil ? .title3.weight(.medium) : .title2.weight(.medium))
            if showsPinyin, let pinyin = tile.pinyin {
                Text(pinyin).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separator), lineWidth: 1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Lays its children out left to right, wrapping onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    /// Centre each line, rather than starting it at the left.
    var centred = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = centred ? bounds.minX + (bounds.width - row.width) / 2 : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
