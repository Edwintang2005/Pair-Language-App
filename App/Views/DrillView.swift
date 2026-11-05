import SwiftUI

/// Which way round a flashcard is asked.
enum CardDirection: Hashable {
    /// Show the German or Chinese word; recall the English.
    case toEnglish
    /// Show the English; recall the German or Chinese word.
    case fromEnglish
}

struct DrillCard: Identifiable, Hashable {
    let id = UUID()
    let word: Word
    let direction: CardDirection
}

/// A round of flashcards that are marked "Got it" or "Missed it". Never touches the review schedule.
/// Used for testing yourself and for quizzing your partner.
struct DrillView: View {
    enum Kind {
        /// You test yourself on your own words.
        case selfTest
        /// You hold the phone; your partner answers out loud.
        case partnerQuiz
    }

    let title: String
    let kind: Kind
    let cards: [DrillCard]

    @Environment(\.dismiss) private var dismiss

    @State private var queue: [DrillCard]
    @State private var revealed = false
    @State private var correct = 0
    @State private var missed: [DrillCard] = []
    @State private var total: Int

    /// What "Done" does. Defaults to closing this screen; Test yourself passes one that closes the
    /// whole sheet, so Done doesn't just step back to the setup screen.
    private let onClose: (() -> Void)?

    init(title: String, kind: Kind, cards: [DrillCard], onClose: (() -> Void)? = nil) {
        self.title = title
        self.kind = kind
        self.cards = cards
        self.onClose = onClose
        // Deal the round here rather than in onAppear, so the first card is there on the first frame.
        // (An onAppear on an empty Group never fires, which left this screen blank.)
        let shuffled = cards.shuffled()
        _queue = State(initialValue: shuffled)
        _total = State(initialValue: shuffled.count)
    }

    var body: some View {
        ZStack {
            if let card = queue.first {
                cardView(card)
            } else {
                results
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { close() }
            }
        }
    }

    // MARK: Card

    private func cardView(_ card: DrillCard) -> some View {
        let word = card.word
        return VStack(spacing: 16) {
            Text("\(total - queue.count + 1) of \(total)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 18) {
                Spacer(minLength: 0)
                switch card.direction {
                case .toEnglish:
                    Text("What does it mean?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    // Pinyin waits for the reveal, so the characters get practised too.
                    HeadwordView(word: word, style: .flashcard, showsPinyin: revealed)
                    SpeakButton(word: word, size: .title2)
                    if revealed {
                        Divider()
                        Text(word.gloss).font(.title2.weight(.semibold))
                        if let grammar = word.grammarLine {
                            Text(grammar).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                case .fromEnglish:
                    Text("How do you say…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(word.gloss)
                        .font(.system(size: 34, weight: .bold))
                    Text(hint(for: word))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if revealed {
                        Divider()
                        HeadwordView(word: word, style: .flashcard)
                        SpeakButton(word: word, size: .title2)
                    }
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card(padding: 20)
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { revealed = true } }

            if revealed {
                HStack(spacing: 10) {
                    Button {
                        next(gotIt: false)
                    } label: {
                        Label("Missed it", systemImage: "xmark").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button {
                        next(gotIt: true)
                    } label: {
                        Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                .font(.headline)
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

    private func hint(for word: Word) -> String {
        switch kind {
        case .selfTest: "Say it in \(word.language.name), then check."
        case .partnerQuiz: "Your partner answers in \(word.language.name)."
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
                Text("\(correct) of \(total)")
                    .font(.largeTitle.bold())
                Text(resultMessage)
                    .foregroundStyle(.secondary)

                if !missed.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(missed) { card in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HeadwordView(word: card.word, style: .medium)
                                    Text(card.word.gloss).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                SpeakButton(word: card.word, size: .body)
                            }
                            .card(padding: 14)
                        }
                    }

                    Button {
                        start(with: missed)
                    } label: {
                        Text("Try the missed ones again").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Done") { close() }
                    .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private var resultMessage: String {
        switch (kind, missed.isEmpty) {
        case (.selfTest, true): "Perfect. You knew them all."
        case (.selfTest, false): "Worth another look:"
        case (.partnerQuiz, true): "A perfect round. Nice teaching!"
        case (.partnerQuiz, false): "Go over these together:"
        }
    }

    // MARK: Actions

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func start(with list: [DrillCard]) {
        // Fresh card identities, so a retry round animates like a new deck.
        queue = list.map { DrillCard(word: $0.word, direction: $0.direction) }.shuffled()
        total = queue.count
        correct = 0
        missed = []
        revealed = false
    }

    private func next(gotIt: Bool) {
        guard let card = queue.first else { return }
        if gotIt { correct += 1 } else { missed.append(card) }
        withAnimation(.snappy) {
            queue.removeFirst()
            revealed = false
        }
    }
}
