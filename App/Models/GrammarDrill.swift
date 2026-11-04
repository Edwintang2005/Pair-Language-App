import Foundation

/// Rules of thumb that explain a German noun's gender.
enum GenderHints {
    /// Endings that are (almost) always one gender.
    static let endings: [(ending: String, gender: String)] = [
        ("ung", "f"), ("heit", "f"), ("keit", "f"), ("schaft", "f"), ("tion", "f"), ("tät", "f"),
        ("chen", "n"), ("lein", "n"),
    ]

    /// The word's own hint if it has one, otherwise a rule from its ending, otherwise nil.
    static func hint(for word: Word) -> String? {
        guard let noun = word.noun else { return nil }
        if let hint = noun.hint { return hint }

        let lower = word.word.lowercased()
        if let rule = endings.first(where: { lower.hasSuffix($0.ending) }) {
            let article = GermanNoun(gender: rule.gender, plural: nil, hint: nil).article
            return rule.gender == noun.gender
                ? "Nouns ending in -\(rule.ending) are always \(article)."
                : "Nouns ending in -\(rule.ending) are usually \(article), but this one is \(noun.article)."
        }
        if lower.hasSuffix("e") {
            return noun.gender == "f"
                ? "Most nouns ending in -e are die."
                : "Most nouns ending in -e are die, but this is one of the exceptions: \(noun.article) \(word.word)."
        }
        return nil
    }
}

/// What Chinese measure words are for, and how a noun is counted.
enum MeasureWords {
    /// What each measure word is used for, in a few words.
    static let uses: [String: String] = [
        "个": "the general one: people, and most things",
        "位": "people, politely",
        "口": "family members",
        "张": "flat things: beds, tables, tickets",
        "条": "long, thin things: roads, rivers, fish",
        "辆": "vehicles",
        "本": "books and magazines",
        "杯": "cups and glasses of something",
        "瓶": "bottles of something",
        "壶": "pots of something",
        "碗": "bowls of something",
        "顿": "meals",
        "间": "rooms",
        "扇": "doors and windows",
        "道": "doors, and dishes of food",
        "所": "schools and hospitals",
        "座": "big things that stay put: cities, buildings, mountains",
        "户": "households",
        "段": "stretches of time or road",
        "块": "chunks, and money (one yuan)",
        "只": "one of a pair, and most animals",
        "双": "pairs: eyes, shoes, chopsticks",
        "件": "clothes, and matters",
        "把": "things with a handle: chairs, knives, umbrellas",
        "种": "kinds or types of something",
        "家": "shops, restaurants and companies",
        "架": "planes",
        "台": "machines: computers, TVs",
        "部": "phones and films",
        "棵": "trees and plants",
        "盏": "lamps and lights",
        "场": "events: weddings, games, films showing",
        "份": "portions and gifts",
        "次": "times something happens",
        "颗": "small round things: hearts, stars, teeth",
        "斤": "half a kilo, for food at the market",
    ]

    /// Wrong answers the drill can offer. 个 comes first because it's the tempting guess.
    static let distractors = ["个", "张", "条", "辆", "本", "只", "件", "把", "杯", "位", "块", "间"]

    /// "一辆车 · yí liàng chē": how to say one of something. Direct nouns use three: 三天.
    static func countingPhrase(for word: Word) -> (text: String, pinyin: String)? {
        guard word.pos == "noun", let pinyin = word.pinyin else { return nil }
        if let measure = word.measureWord {
            // 个 is said with a neutral tone, and 一 changes tone before it: yí ge.
            let measurePinyin = measure.word == "个" ? "ge" : measure.pinyin
            let yi = isFourthTone(measure.pinyin) ? "yí" : "yì"
            return ("一\(measure.word)\(word.word)", "\(yi) \(measurePinyin) \(pinyin)")
        }
        if word.countsDirectly {
            return ("三\(word.word)", "sān \(pinyin)")
        }
        return nil
    }

    static func isFourthTone(_ pinyin: String) -> Bool {
        pinyin.contains { "àèìòùǜ".contains($0) }
    }
}

/// One multiple-choice question in the grammar drill:
/// "Haus: der, die or das?" or "车: which measure word?"
struct GrammarQuestion: Identifiable, Hashable {
    let id = UUID()
    let word: Word
    /// The buttons, in order.
    let options: [String]
    /// The usual answer, shown as the correct one.
    let answer: String
    /// Every option that counts as right (the usual answer plus any alternatives).
    let accepted: Set<String>

    func isCorrect(_ option: String) -> Bool { accepted.contains(option) }
}

enum GrammarDrill {
    /// The option for nouns that are counted with no measure word (三天).
    static let noMeasureWord = "none"

    /// What the drill is called for someone learning this language.
    static func title(for language: Language) -> String {
        language == .german ? "der, die or das?" : "Measure words"
    }

    /// Whether a word has something to drill: German nouns, and Chinese nouns that can be counted.
    static func isEligible(_ word: Word) -> Bool {
        guard word.pos == "noun" else { return false }
        switch word.language {
        case .german: return word.noun != nil
        case .chinese: return word.measureWord != nil || word.countsDirectly
        }
    }

    static func question<G: RandomNumberGenerator>(for word: Word, using rng: inout G) -> GrammarQuestion? {
        guard isEligible(word) else { return nil }
        if let noun = word.noun {
            // Always in the same order, so your thumb learns where each one is.
            return GrammarQuestion(word: word, options: ["der", "die", "das"],
                                   answer: noun.article, accepted: [noun.article])
        }
        let answer = word.measureWord?.word ?? noMeasureWord
        let accepted = Set([answer] + (word.measureWord?.also ?? []))
        let wrong = MeasureWords.distractors.filter { !accepted.contains($0) }
        // Four measure words to choose from. 个 stays in as the tempting guess when it's wrong.
        var choices = answer == noMeasureWord ? [] : [answer]
        choices += wrong.prefix(1)
        choices += wrong.dropFirst().shuffled(using: &rng).prefix(4 - choices.count)
        // "No measure word" is always last, so it's a real choice on every question.
        let options = choices.shuffled(using: &rng) + [noMeasureWord]
        return GrammarQuestion(word: word, options: options, answer: answer, accepted: accepted)
    }

    /// A round of up to `limit` questions from these words, in random order.
    static func questions<G: RandomNumberGenerator>(wordIDs: [String], content: ContentLibrary,
                                                    limit: Int = 20, using rng: inout G) -> [GrammarQuestion] {
        wordIDs
            .compactMap { content.words[$0] }
            .filter(isEligible)
            .shuffled(using: &rng)
            .prefix(limit)
            .compactMap { question(for: $0, using: &rng) }
    }

    static func questions(wordIDs: [String], content: ContentLibrary, limit: Int = 20) -> [GrammarQuestion] {
        var rng = SystemRandomNumberGenerator()
        return questions(wordIDs: wordIDs, content: content, limit: limit, using: &rng)
    }
}

/// Short notes about a word's grammar: the rule of thumb behind it, and something
/// the teaching partner can get the learner to say out loud.
enum GrammarNotes {
    /// Why a noun has its gender or measure word, when there's a pattern worth knowing.
    static func pattern(for word: Word) -> String? {
        if word.noun != nil { return GenderHints.hint(for: word) }
        if let measure = word.measureWord, let use = MeasureWords.uses[measure.word] {
            return "\(measure.word) is for \(use)."
        }
        if word.countsDirectly { return "No measure word: the number goes straight in front." }
        return nil
    }

    /// For the teacher: a quick way to practise the word's grammar together.
    static func practice(for word: Word) -> String? {
        if let noun = word.noun {
            let base = "Say \"\(word.word)\" on its own and have them add the article: \(word.headword)."
            guard let plural = noun.plural else { return base }
            return base + " Then ask for two of them: zwei \(plural)."
        }
        if let verb = word.verb {
            let aux = verb.auxiliary == "sein" ? "ist" : "hat"
            return "Have them say it about someone else, then in the past: er \(verb.present3sg), er \(aux) \(verb.participle)."
        }
        if let measure = word.measureWord {
            return "Point at one and have them count it: 一\(measure.word)\(word.word), then 两\(measure.word)\(word.word)."
        }
        if word.countsDirectly {
            return "Have them say three of them: 三\(word.word). Nothing goes in between."
        }
        return nil
    }
}
