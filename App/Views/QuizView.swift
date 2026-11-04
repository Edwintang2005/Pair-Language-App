import SwiftUI

/// You hold the phone; your partner answers out loud. Shows the English, then reveals their word.
/// Nothing is saved: it's for revising together, and it never touches anyone's review schedule.
struct QuizView: View {
    let language: Language
    let words: [Word]

    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Word] = []
    @State private var revealed = false
    @State private var correct = 0
    @State private var missed: [Word] = []
    @State private var total = 0

    var body: some View {
        NavigationStack {
            Group {
                if let word = queue.first {
                    card(word)
                } else {
                    results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Quiz your partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { start(with: words) }
    }

    private func card(_ word: Word) -> some View {
        VStack(spacing: 16) {
            Text("\(total - queue.count + 1) of \(total)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 18) {
                Spacer(minLength: 0)
                Text("How do you say…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(word.gloss)
                    .font(.system(size: 34, weight: .bold))
                Text("Your partner answers in \(language.name).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if revealed {
                    Divider()
                    HeadwordView(word: word, style: .flashcard)
                    SpeakButton(word: word, size: .title2)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card(padding: 20)

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

    private var results: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: missed.isEmpty ? "star.fill" : "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(missed.isEmpty ? Color.yellow : Color.green)
                    .padding(.top, 32)
                Text("\(correct) of \(total)")
                    .font(.largeTitle.bold())
                Text(missed.isEmpty ? "A perfect round. Nice teaching!" : "Go over these together:")
                    .foregroundStyle(.secondary)

                if !missed.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(missed) { word in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HeadwordView(word: word, style: .medium)
                                    Text(word.gloss).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                SpeakButton(word: word, size: .body)
                            }
                            .card(padding: 14)
                        }
                    }

                    Button {
                        start(with: missed)
                    } label: {
                        Text("Quiz the missed words again").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Done") { dismiss() }
                    .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private func start(with list: [Word]) {
        queue = list.shuffled()
        total = queue.count
        correct = 0
        missed = []
        revealed = false
    }

    private func next(gotIt: Bool) {
        guard let word = queue.first else { return }
        if gotIt { correct += 1 } else { missed.append(word) }
        withAnimation(.snappy) {
            queue.removeFirst()
            revealed = false
        }
    }
}
