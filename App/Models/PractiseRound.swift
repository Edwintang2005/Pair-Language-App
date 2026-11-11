import Foundation

/// One step of the mixed Practise round.
enum PractiseItem: Identifiable {
    case choice(ChoiceQuestion)
    /// Always in Listen mode: hear it, build it.
    case sentence(SentencePuzzle)
    case speaking(SpeakingItem)

    var id: UUID {
        switch self {
        case .choice(let q): q.id
        case .sentence(let p): p.id
        case .speaking(let s): s.id
        }
    }

    /// Speaking isn't marked right or wrong.
    var isMarked: Bool {
        if case .speaking = self { return false }
        return true
    }
}

/// "Practise · 5 minutes": a short mix of drills, aimed at listening and speaking, using your
/// weakest words first.
enum PractiseRound {
    enum Slot: Equatable {
        case choice(ChoiceDrill)
        case sentence
        case speaking
    }

    /// The round's shape, alternating kinds so it never feels like one drill.
    static func slots(for language: Language) -> [Slot] {
        switch language {
        case .chinese:
            [.choice(.tones), .choice(.listening), .sentence, .choice(.grammar),
             .choice(.tones), .choice(.listening), .sentence, .speaking]
        case .german:
            [.choice(.grammar), .choice(.listening), .sentence, .choice(.plurals),
             .choice(.listening), .choice(.pastTense), .sentence, .speaking]
        }
    }

    /// The round needs a few words before the options make sense.
    static let minimumWords = 4

    /// - Parameter box: each word's Leitner box (nil for taught but never reviewed: the weakest).
    static func items<G: RandomNumberGenerator>(language: Language, knownIDs: [String], box: (String) -> Int?,
                                                content: ContentLibrary, using rng: inout G) -> [PractiseItem] {
        let known = knownIDs.compactMap { content.words[$0] }.filter { $0.language == language }
        guard known.count >= minimumWords else { return [] }
        // Weakest first. Shuffling before a (stable) sort mixes up words of the same strength, so it
        // isn't the same words every time.
        let candidates = known.shuffled(using: &rng).sorted { (box($0.id) ?? 0) < (box($1.id) ?? 0) }

        var used: Set<String> = []
        var items: [PractiseItem] = []
        for slot in slots(for: language) {
            for word in candidates where !used.contains(word.id) {
                guard let item = item(for: slot, word: word, pool: known, content: content, using: &rng) else { continue }
                used.insert(word.id)
                items.append(item)
                break
            }
        }
        return items
    }

    static func items(language: Language, knownIDs: [String], box: (String) -> Int?,
                      content: ContentLibrary) -> [PractiseItem] {
        var rng = SystemRandomNumberGenerator()
        return items(language: language, knownIDs: knownIDs, box: box, content: content, using: &rng)
    }

    private static func item<G: RandomNumberGenerator>(for slot: Slot, word: Word, pool: [Word],
                                                      content: ContentLibrary, using rng: inout G) -> PractiseItem? {
        switch slot {
        case .choice(let drill):
            guard drill.isEligible(word),
                  let question = drill.question(for: word, pool: pool, content: content, using: &rng) else { return nil }
            return .choice(question)
        case .sentence:
            return SentenceBuilder.puzzle(for: word, content: content, using: &rng).map(PractiseItem.sentence)
        case .speaking:
            return SpeakingItem.item(for: word, content: content, using: &rng).map(PractiseItem.speaking)
        }
    }
}
