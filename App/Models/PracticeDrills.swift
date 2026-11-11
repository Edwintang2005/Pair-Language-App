import Foundation

/// The tap-the-answer drills on the Review tab. All are marked by the app and never touch the
/// review schedule.
enum ChoiceDrill: String, Identifiable, CaseIterable {
    /// der/die/das for German, measure words for Chinese. See `GrammarDrill`.
    case grammar
    /// German plurals: das Haus → die Häuser.
    case plurals
    /// German past tense: gehen → er ist gegangen. Covers haben or sein as well.
    case pastTense
    /// Hear a word, pick its meaning. Both languages.
    case listening
    /// Chinese: hear a word, pick its tones (老师: 3 + 1).
    case tones

    var id: String { rawValue }

    /// The drills someone learning this language gets, in the order the Review tab shows them.
    static func drills(for language: Language) -> [ChoiceDrill] {
        language == .german ? [.grammar, .plurals, .pastTense, .listening] : [.grammar, .tones, .listening]
    }

    func title(for language: Language) -> String {
        switch self {
        case .grammar: GrammarDrill.drillTitle(for: language)
        case .plurals: "Plurals"
        case .pastTense: "Past tense"
        case .listening: "Listening"
        case .tones: "Tones"
        }
    }

    /// The question above the word.
    func prompt(for language: Language) -> String {
        switch self {
        case .grammar: language == .german ? "der, die or das?" : "Which measure word?"
        case .plurals: "What's the plural?"
        case .pastTense: "Say it in the past"
        case .listening: "What did you hear?"
        case .tones: "Which tones did you hear?"
        }
    }

    func isEligible(_ word: Word) -> Bool {
        switch self {
        case .grammar: GrammarDrill.isEligible(word)
        case .plurals: Plurals.isEligible(word)
        case .pastTense: PastTense.isEligible(word)
        case .listening: true
        case .tones: Tones.isEligible(word)
        }
    }

    /// One question about `word`. Listening picks its wrong answers from `pool` (the words you know),
    /// topping up from the rest of the content when you don't know enough yet.
    func question<G: RandomNumberGenerator>(for word: Word, pool: [Word], content: ContentLibrary,
                                            using rng: inout G) -> ChoiceQuestion? {
        switch self {
        case .grammar: GrammarDrill.question(for: word, using: &rng)
        case .plurals: Plurals.question(for: word, using: &rng)
        case .pastTense: PastTense.question(for: word, using: &rng)
        case .listening: Listening.question(for: word, pool: pool, content: content, using: &rng)
        case .tones: Tones.question(for: word, using: &rng)
        }
    }

    /// A round of up to `limit` questions from these words, in random order.
    func questions<G: RandomNumberGenerator>(wordIDs: [String], content: ContentLibrary, limit: Int = 20,
                                             using rng: inout G) -> [ChoiceQuestion] {
        let words = wordIDs.compactMap { content.words[$0] }
        return words
            .filter(isEligible)
            .shuffled(using: &rng)
            .prefix(limit)
            .compactMap { question(for: $0, pool: words, content: content, using: &rng) }
    }

    func questions(wordIDs: [String], content: ContentLibrary, limit: Int = 20) -> [ChoiceQuestion] {
        var rng = SystemRandomNumberGenerator()
        return questions(wordIDs: wordIDs, content: content, limit: limit, using: &rng)
    }

    /// How many of these words the drill can use.
    func eligibleCount(in wordIDs: [String], content: ContentLibrary) -> Int {
        wordIDs.filter { content.words[$0].map(isEligible) ?? false }.count
    }
}

// MARK: - Plurals

/// German plurals: one right answer and three wrong ones built from the common patterns.
enum Plurals {
    static func isEligible(_ word: Word) -> Bool {
        guard let plural = word.noun?.plural else { return false }
        return !plural.isEmpty
    }

    static func question<G: RandomNumberGenerator>(for word: Word, using rng: inout G) -> ChoiceQuestion? {
        guard isEligible(word), let answer = word.noun?.plural else { return nil }
        var wrong: [String] = []
        for option in likelyForms(of: word.word).shuffled(using: &rng) + otherForms(of: word.word)
        where option != answer && !wrong.contains(option) && !notWrong.contains(option) {
            wrong.append(option)
        }
        guard wrong.count >= 3 else { return nil }
        let options = ([answer] + wrong.prefix(3)).shuffled(using: &rng)
        return ChoiceQuestion(word: word, options: options, answer: answer, accepted: [answer], kind: .plurals)
    }

    /// Forms the pattern rules could produce that aren't actually wrong (die Worte, die Dinger,
    /// die Bänke for benches) or are other words entirely (der Busen).
    /// Also less common or regional plurals (die Parke, die Lichte), and other senses of the word
    /// (die Muttern: nuts, for bolts).
    static let notWrong: Set<String> = ["Worte", "Dinger", "Bänke", "Busen",
                                        "Parke", "Pärke", "Muttern", "Laden", "Munde", "Münde", "Lichte"]

    /// The word with an umlaut on the vowel of its last real syllable: Haus → Häus, Apfel → Äpfel,
    /// Laden → Läden. Nil when that vowel can't take one (Freund, Arbeit, Tier) or ends the word (Auto).
    static func umlauted(_ word: String) -> String? {
        var chars = Array(word)
        let lower = word.lowercased()
        // Look past an unstressed ending: Mutter → Mutt, Blume → Blum.
        var end = chars.count
        if let suffix = ["el", "er", "en", "e"].first(where: { lower.hasSuffix($0) && chars.count > $0.count + 1 }) {
            end -= suffix.count
        }
        let vowels = Set("aeiouyäöüAEIOUYÄÖÜ")
        var last = end - 1
        while last >= 0 && !vowels.contains(chars[last]) { last -= 1 }
        guard last >= 0, last < chars.count - 1 else { return nil }
        var first = last
        while first > 0 && vowels.contains(chars[first - 1]) { first -= 1 }

        let marked: [Character: Character] = ["a": "ä", "o": "ö", "u": "ü", "A": "Ä", "O": "Ö", "U": "Ü"]
        switch String(chars[first...last]).lowercased() {
        case "a", "o", "u":
            chars[first] = marked[chars[first]] ?? chars[first]
        case "au":
            chars[first] = marked[chars[first]] ?? chars[first]
        default:
            return nil  // ei, eu, ie, aa, oo…
        }
        return String(chars)
    }

    /// Wrong answers that look right for this kind of word.
    private static func likelyForms(of word: String) -> [String] {
        let lower = word.lowercased()
        let umlaut = umlauted(word)
        if lower.hasSuffix("e") {
            return [word + "n", word + "s", word, umlaut.map { $0 + "n" }].compactMap { $0 }
        }
        if endsInUnstressedSyllable(lower) {
            // Schlüssel, Lehrer, Laden: no -e or -er on the end, but -n is tempting for -el and -er.
            let n = lower.hasSuffix("en") ? nil : word + "n"
            return [word, umlaut, n, word + "s"].compactMap { $0 }
        }
        return [word + "e", word + "er", word + "en", word + "s",
                umlaut.map { $0 + "e" }, umlaut.map { $0 + "er" }].compactMap { $0 }
    }

    /// -el, -er or -en after a consonant: Vogel, Fenster, Laden (not Spiel, Tier or Meer).
    static func endsInUnstressedSyllable(_ lower: String) -> Bool {
        guard ["el", "er", "en"].contains(where: lower.hasSuffix), lower.count > 2 else { return false }
        let before = lower[lower.index(lower.endIndex, offsetBy: -3)]
        return !"aeiouäöüy".contains(before)
    }

    /// A fallback so there are always three wrong answers.
    private static func otherForms(of word: String) -> [String] {
        let base = word.hasSuffix("e") ? String(word.dropLast()) : word
        return [base + "en", base + "er", base + "s", word, base + "e"]
    }

    /// What happens to the word, and the rule behind it when there's one worth knowing.
    static func explanation(for word: Word) -> String? {
        guard let noun = word.noun, let plural = noun.plural, !plural.isEmpty else { return nil }
        let singular = word.word
        let lower = singular.lowercased()
        let umlaut = umlauted(singular)

        let change: String
        var ending = ""
        if plural == singular {
            change = "It stays the same"
        } else if plural == umlaut {
            change = "It just gets an umlaut"
        } else if let umlaut, plural.hasPrefix(umlaut), plural != singular, !plural.hasPrefix(singular) {
            ending = String(plural.dropFirst(umlaut.count))
            change = "It adds -\(ending) and an umlaut"
        } else if plural.hasPrefix(singular) {
            ending = String(plural.dropFirst(singular.count))
            change = "It adds -\(ending)"
        } else {
            change = "It's irregular"
        }

        let rule: String? = {
            let endsWith = { (suffixes: [String]) in suffixes.contains(where: lower.hasSuffix) }
            if endsWith(["chen", "lein"]) && plural == singular {
                return "-chen and -lein words never change."
            }
            if endsWith(["ung", "heit", "keit", "schaft", "tion", "tät"]) && ending == "en" {
                return "-ung, -heit, -keit, -schaft, -tion and -tät words always add -en."
            }
            if noun.gender == "f" && lower.hasSuffix("in") && ending == "nen" {
                return "-in words add -nen."
            }
            if noun.gender == "f" && lower.hasSuffix("e") && ending == "n" {
                return "Almost every die-word ending in -e adds -n."
            }
            if noun.gender != "f" && endsInUnstressedSyllable(lower) && (plural == singular || plural == umlaut) {
                return "der and das words ending in -el, -er or -en usually add nothing, sometimes just an umlaut."
            }
            if ending == "s" {
                return "Words ending in a vowel other than -e, and many borrowed words, add -s."
            }
            if noun.gender == "n" && ending == "er" {
                return "Lots of das-words add -er, with an umlaut where they can."
            }
            if noun.gender == "m" && ending == "e" {
                return "Lots of der-words add -e, often with an umlaut."
            }
            return nil
        }()
        return ["\(change): die \(plural).", rule].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Past tense

/// German past tense (Perfekt): pick "ist gegangen" from hat/ist × the right participle/a made-up one.
enum PastTense {
    /// Modal verbs are left out: people say "er konnte", not "er hat gekonnt". sich erinnern needs "sich".
    static let skipped: Set<String> = ["de-wollen", "de-moegen", "de-koennen", "de-muessen", "de-duerfen",
                                       "de-sollen", "de-erinnern"]

    static func isEligible(_ word: Word) -> Bool {
        // The headword has to be the infinitive (session 3 teaches "ist", not "sein").
        word.verb != nil && word.word.hasSuffix("n") && !skipped.contains(word.id)
    }

    static func auxiliary(for verb: GermanVerb) -> String { verb.auxiliary == "sein" ? "ist" : "hat" }

    static func question<G: RandomNumberGenerator>(for word: Word, using rng: inout G) -> ChoiceQuestion? {
        guard isEligible(word), let verb = word.verb, let fake = madeUpParticiple(for: word) else { return nil }
        let right = auxiliary(for: verb)
        let wrong = right == "ist" ? "hat" : "ist"
        let answer = "\(right) \(verb.participle)"
        let options = ["\(right) \(verb.participle)", "\(wrong) \(verb.participle)",
                       "\(right) \(fake)", "\(wrong) \(fake)"].shuffled(using: &rng)
        return ChoiceQuestion(word: word, options: options, answer: answer, accepted: [answer], kind: .pastTense)
    }

    /// Where the participle's ge- goes: at the front (gemacht), after a separable prefix
    /// (aufgestanden), or nowhere (verstanden, repariert).
    enum GePlacement: Equatable {
        case front
        case afterPrefix(String)
        case none
    }

    static func gePlacement(infinitive: String, participle: String) -> GePlacement {
        // gehen → gegangen and geben → gegeben add a ge- in front of their own g;
        // gewinnen → gewonnen and gehören → gehört don't.
        if participle.hasPrefix("ge") && (!infinitive.hasPrefix("ge") || participle.dropFirst(2).hasPrefix("g")) {
            return .front
        }
        // Only real separable prefixes: vergessen and begegnen have a "ge" of their own.
        if let range = participle.range(of: "ge"), range.lowerBound != participle.startIndex {
            let prefix = String(participle[..<range.lowerBound])
            if separablePrefixes.contains(prefix) && infinitive.hasPrefix(prefix) {
                return .afterPrefix(prefix)  // aufgestanden, and aufgegeben too
            }
        }
        return .none
    }

    /// Prefixes that split off and take the ge- after them.
    static let separablePrefixes: Set<String> = [
        "ab", "an", "auf", "aus", "bei", "ein", "fern", "fest", "her", "hin", "los", "mit", "nach",
        "vor", "weg", "zu", "zurück", "zusammen", "weiter", "heim",
    ]

    /// The participle a regular verb would have: ge- + stem + -t, with the ge- after any separable
    /// prefix (gemacht, aufgeräumt). Nil for verbs that take no ge-.
    static func regularParticiple(for word: Word) -> String? {
        guard let participle = word.verb?.participle else { return nil }
        let infinitive = word.word
        let prefix: String
        switch gePlacement(infinitive: infinitive, participle: participle) {
        case .front: prefix = ""
        case .afterPrefix(let p): prefix = p
        case .none: return nil
        }
        let stem = stem(of: String(infinitive.dropFirst(prefix.count)))
        return prefix + "ge" + stem + weakEnding(for: stem)
    }

    /// -et after t or d (gearbeitet), and after m or n that follow another consonant (geöffnet,
    /// geregnet, geatmet); -t otherwise (gelernt, gewohnt).
    static func weakEnding(for stem: String) -> String {
        let letters = Array(stem.lowercased())
        guard let last = letters.last else { return "t" }
        if last == "t" || last == "d" { return "et" }
        if (last == "m" || last == "n"), letters.count >= 2 {
            let before = letters[letters.count - 2]
            if !"aeiouäöüylrhmn".contains(before) { return "et" }
        }
        return "t"
    }

    private static func stem(of infinitive: String) -> String {
        infinitive.hasSuffix("en") ? String(infinitive.dropLast(2)) : String(infinitive.dropLast())
    }

    /// A participle a learner might guess: the regular -t form for irregular verbs (gegeht),
    /// the -en form for regular ones (gemachen), and a stray ge- for verbs that don't take one (gerepariert).
    static func madeUpParticiple(for word: Word) -> String? {
        guard let participle = word.verb?.participle else { return nil }
        guard let regular = regularParticiple(for: word) else { return "ge" + participle }
        if regular != participle { return regular }
        // Regular verbs: swap the -t for -en (gemacht → gemachen).
        let strong = String(regular.dropLast(regular.hasSuffix("et") ? 2 : 1)) + "en"
        return strong != participle ? strong : nil
    }

    /// Why it's haben or sein, and anything odd about the participle.
    static func explanation(for word: Word) -> String? {
        guard let verb = word.verb else { return nil }
        var lines: [String] = []
        if word.word == "bleiben" {
            lines.append("It takes sein, even though nothing moves or changes: bleiben is the exception to learn.")
        } else {
            lines.append(verb.auxiliary == "sein"
                ? "It takes sein: verbs for moving from place to place, or for a change of state, do."
                : "It takes haben, like most verbs.")
        }
        let regular = regularParticiple(for: word)
        switch gePlacement(infinitive: word.word, participle: verb.participle) {
        case .afterPrefix(let prefix):
            lines.append("The ge- goes after the prefix: \(prefix)·ge·\(verb.participle.dropFirst(prefix.count + 2)).")
        case .none:
            lines.append(verb.participle.hasSuffix("iert")
                ? "Verbs ending in -ieren never take ge-."
                : "No ge- here: verbs starting with be-, er-, ge-, ver- and similar leave it off.")
        case .front:
            if regular == verb.participle, let ending = ["et", "t"].first(where: verb.participle.hasSuffix) {
                let stem = verb.participle.dropFirst(2).dropLast(ending.count)
                lines.append("It's regular: ge- + \(stem) + -\(ending).")
            }
        }
        if let regular, regular != verb.participle {
            lines.append("It's irregular, so \(verb.participle) has to be learnt (not \(regular)).")
        }
        return lines.joined(separator: " ")
    }
}

// MARK: - Listening

/// Hear a word, then pick its meaning from four.
enum Listening {
    static func question<G: RandomNumberGenerator>(for word: Word, pool: [Word], content: ContentLibrary,
                                                   using rng: inout G) -> ChoiceQuestion? {
        let answer = word.shortGloss
        var seen: Set<String> = [answer.lowercased()]
        var wrong: [String] = []

        let sound = soundKey(word)
        func take(from words: [Word]) {
            for other in words where wrong.count < 3 {
                let gloss = other.shortGloss
                guard other.language == word.language, !seen.contains(gloss.lowercased()) else { continue }
                // Words that sound exactly the same (他/她 tā, 做/坐 zuò) can't be told apart by ear.
                guard soundKey(other) != sound else { continue }
                seen.insert(gloss.lowercased())
                wrong.append(gloss)
            }
        }
        // Same part of speech first, so you can't rule options out by grammar alone.
        let known = pool.filter { $0.id != word.id }.shuffled(using: &rng)
        take(from: known.filter { $0.pos == word.pos })
        take(from: known)
        if wrong.count < 3 {
            let everything = content.words.values.sorted { $0.id < $1.id }.shuffled(using: &rng)
            take(from: everything.filter { $0.pos == word.pos })
            take(from: everything)
        }
        guard wrong.count == 3 else { return nil }
        let options = ([answer] + wrong).shuffled(using: &rng)
        return ChoiceQuestion(word: word, options: options, answer: answer, accepted: [answer], kind: .listening)
    }

    /// What a word sounds like, for spotting homophones: pinyin with tones for Chinese, the spoken
    /// form for German.
    static func soundKey(_ word: Word) -> String {
        let spoken = word.pinyin ?? word.headword
        return spoken.lowercased().filter { !$0.isWhitespace && $0 != "'" }
    }
}

// MARK: - Tones

/// Chinese tones, read from the pinyin's tone marks: 1–4, and 0 for the neutral tone.
enum Tones {
    /// The syllables a tone question can have: one to three (老师, 不客气).
    static let syllableRange = 1...3

    /// One tone per syllable: "lǎoshī" → [3, 1], "péngyou" → [2, 0], "yìdiǎnr" → [4, 3].
    /// Syllables are runs of vowels, as in `SentenceBuilder.characterCount`.
    static func pattern(ofPinyin pinyin: String) -> [Int] {
        var tones: [Int] = []
        for part in pinyin.split(whereSeparator: { $0.isWhitespace || $0 == "'" || $0 == "-" }) {
            var syllable: Int?
            for character in part.lowercased() {
                let scalars = String(character).decomposedStringWithCanonicalMapping.unicodeScalars
                guard let base = scalars.first, "aeiou".unicodeScalars.contains(base) else {
                    if let tone = syllable { tones.append(tone); syllable = nil }
                    continue
                }
                let mark = scalars.dropFirst().compactMap(toneMarks.firstIndex(of:)).first.map { $0 + 1 }
                syllable = max(syllable ?? 0, mark ?? 0)
            }
            if let tone = syllable { tones.append(tone) }
        }
        return tones
    }

    /// Combining macron, acute, caron and grave: tones 1 to 4.
    private static let toneMarks: [Unicode.Scalar] = ["\u{0304}", "\u{0301}", "\u{030C}", "\u{0300}"]

    static func pattern(of word: Word) -> [Int] {
        word.pinyin.map(pattern(ofPinyin:)) ?? []
    }

    static func isEligible(_ word: Word) -> Bool {
        let tones = pattern(of: word)
        // A word can't start on a neutral tone; if it seems to, the pinyin is missing a mark.
        return word.language == .chinese && syllableRange.contains(tones.count) && tones.first != 0
    }

    /// "3-1": how a pattern is stored as an answer option.
    static func label(_ tones: [Int]) -> String { tones.map(String.init).joined(separator: "-") }

    static func tones(fromLabel label: String) -> [Int] { label.split(separator: "-").compactMap { Int($0) } }

    /// How it sounds when two 3rd tones meet: the first becomes a 2nd (你好: 3-3 is said 2-3).
    /// Nil when nothing changes.
    static func spoken(_ tones: [Int]) -> [Int]? {
        var said = tones
        for i in said.indices.dropLast() where said[i] == 3 && said[i + 1] == 3 { said[i] = 2 }
        return said == tones ? nil : said
    }

    static func question<G: RandomNumberGenerator>(for word: Word, using rng: inout G) -> ChoiceQuestion? {
        guard isEligible(word) else { return nil }
        let tones = pattern(of: word)
        let answer = label(tones)
        if tones.count == 1 {
            // Always 1 2 3 4, so your thumb learns where each one is.
            return ChoiceQuestion(word: word, options: ["1", "2", "3", "4"], answer: answer,
                                  accepted: [answer], kind: .tones)
        }
        // 你好 is written 3-3 but heard 2-3: both are right, and the explanation says why.
        let said = spoken(tones).map(label)
        var options = [answer] + (said.map { [$0] } ?? [])
        // Wrong answers differ by one tone first, so it's your ear doing the work.
        var oneOff: [String] = []
        for i in tones.indices {
            for tone in (i == 0 ? [1, 2, 3, 4] : [1, 2, 3, 4, 0]) where tone != tones[i] {
                var other = tones
                other[i] = tone
                oneOff.append(label(other))
            }
        }
        for option in oneOff.shuffled(using: &rng) where options.count < 4 && !options.contains(option) {
            options.append(option)
        }
        return ChoiceQuestion(word: word, options: options.shuffled(using: &rng), answer: answer,
                              accepted: Set([answer] + (said.map { [$0] } ?? [])), kind: .tones)
    }

    static func name(of tone: Int) -> String {
        switch tone {
        case 1: "1st, high and level"
        case 2: "2nd, rising"
        case 3: "3rd, low and dipping"
        case 4: "4th, falling"
        default: "neutral, light and short"
        }
    }

    /// What each tone is, plus the tone changes that catch people out.
    static func explanation(for word: Word) -> String? {
        let tones = pattern(of: word)
        guard !tones.isEmpty else { return nil }
        // Words never start on a neutral tone, so this always starts with a number: "3rd, low… + 1st, high…".
        var lines = [tones.map(name(of:)).joined(separator: " + ") + "."]
        if let said = spoken(tones) {
            lines.append("Two 3rd tones in a row: the first is said as a 2nd, so you hear \(said.map(String.init).joined(separator: " + ")).")
        }
        if word.word.contains("不") {
            lines.append("不 is bù, but bú before a 4th tone.")
        }
        if word.word.contains("一") {
            lines.append("一 is yī on its own, yì before a 1st, 2nd or 3rd tone, and yí before a 4th.")
        }
        return lines.joined(separator: " ")
    }
}

// MARK: - Sentence building

/// One word (German) or one pinyin-spaced word (Chinese) of an example sentence.
struct SentenceTile: Identifiable, Hashable {
    let id: Int
    let text: String
    let pinyin: String?
}

/// "Put the words in order" for one example sentence.
struct SentencePuzzle: Identifiable, Hashable {
    let id = UUID()
    let word: Word
    let example: Example
    /// In the right order.
    let tiles: [SentenceTile]
    /// The order they're offered in.
    let shuffled: [SentenceTile]

    /// Compared by text, so two identical tiles ("die … die") can go either way round.
    func isCorrect(_ answer: [SentenceTile]) -> Bool {
        answer.map(\.text) == tiles.map(\.text)
    }
}

enum SentenceBuilder {
    static let minTiles = 3
    static let maxTiles = 10

    private static let punctuation = CharacterSet(charactersIn: ",.?!:;\"'„“”‚‘’«»…–—，。？！、：；“”‘’《》（）")
    /// Pinyin that stays capitalised at the start of a sentence.
    static let properNouns: Set<String> = ["Zhōngguó", "Déguó", "Běijīng", "Shànghǎi", "Zhōngwén", "Déyǔ",
                                           "Yīngyǔ", "Bólín", "Hànyǔ"]

    static func isEligible(_ word: Word, content: ContentLibrary) -> Bool {
        word.examples.contains { tiles(for: $0, language: word.language, content: content) != nil }
    }

    static func puzzle<G: RandomNumberGenerator>(for word: Word, content: ContentLibrary,
                                                 using rng: inout G) -> SentencePuzzle? {
        for example in word.examples {
            guard let tiles = tiles(for: example, language: word.language, content: content) else { continue }
            var shuffled = tiles.shuffled(using: &rng)
            // Never hand over the answer already in order.
            for _ in 0..<10 where shuffled.map(\.text) == tiles.map(\.text) {
                shuffled = tiles.shuffled(using: &rng)
            }
            guard shuffled.map(\.text) != tiles.map(\.text) else { continue }
            return SentencePuzzle(word: word, example: example, tiles: tiles, shuffled: shuffled)
        }
        return nil
    }

    static func puzzles<G: RandomNumberGenerator>(wordIDs: [String], content: ContentLibrary, limit: Int = 10,
                                                  using rng: inout G) -> [SentencePuzzle] {
        var puzzles: [SentencePuzzle] = []
        for word in wordIDs.compactMap({ content.words[$0] }).shuffled(using: &rng) where puzzles.count < limit {
            if let puzzle = puzzle(for: word, content: content, using: &rng) { puzzles.append(puzzle) }
        }
        return puzzles
    }

    static func puzzles(wordIDs: [String], content: ContentLibrary, limit: Int = 10) -> [SentencePuzzle] {
        var rng = SystemRandomNumberGenerator()
        return puzzles(wordIDs: wordIDs, content: content, limit: limit, using: &rng)
    }

    static func eligibleCount(in wordIDs: [String], content: ContentLibrary) -> Int {
        wordIDs.filter { id in content.words[id].map { isEligible($0, content: content) } ?? false }.count
    }

    /// The sentence cut into tiles, without punctuation. Nil when it's too short or too long, or
    /// (Chinese) when the pinyin doesn't line up with the characters.
    static func tiles(for example: Example, language: Language, content: ContentLibrary) -> [SentenceTile]? {
        guard let tiles = words(of: example, language: language, content: content),
              (minTiles...maxTiles).contains(tiles.count) else { return nil }
        return tiles
    }

    /// The sentence cut into words, however many there are. Nil when (Chinese) the pinyin doesn't
    /// line up with the characters.
    static func words(of example: Example, language: Language, content: ContentLibrary) -> [SentenceTile]? {
        language == .german
            ? germanTiles(example.text, content: content)
            : chineseTiles(example.text, pinyin: example.pinyin)
    }

    private static func strip(_ token: some StringProtocol) -> String {
        String(token).trimmingCharacters(in: punctuation)
    }

    // MARK: German

    private static func germanTiles(_ text: String, content: ContentLibrary) -> [SentenceTile]? {
        var words = text.split(whereSeparator: \.isWhitespace).map(strip).filter { !$0.isEmpty }
        // Lower-case the first word so its capital doesn't give away where it goes. Nouns, names and
        // "Sie" keep theirs: words that are capitalised mid-sentence or are noun headwords, unless
        // they're also lower-case mid-sentence (morgen / der Morgen).
        if let first = words.first, first != "Sie" {
            let lowered = first.prefix(1).lowercased() + first.dropFirst()
            let mid = midSentenceWords(in: content)
            let isNoun = mid.contains(first) || nounHeadwords(in: content).contains(first)
            if mid.contains(lowered) || !isNoun {
                words[0] = lowered
            }
        }
        return words.enumerated().map { SentenceTile(id: $0.offset, text: $0.element, pinyin: nil) }
    }

    private static var cachedMidSentenceWords: Set<String>?

    private static var cachedNounHeadwords: Set<String>?

    /// Haus, Wasser, Obst…
    static func nounHeadwords(in content: ContentLibrary) -> Set<String> {
        if let cached = cachedNounHeadwords { return cached }
        let nouns = Set(content.words.values.filter { $0.noun != nil }.map(\.word))
        cachedNounHeadwords = nouns
        return nouns
    }

    /// Every word that appears after the first in a German example.
    static func midSentenceWords(in content: ContentLibrary) -> Set<String> {
        if let cached = cachedMidSentenceWords { return cached }
        var words: Set<String> = []
        for word in content.words.values where word.language == .german {
            for example in word.examples {
                for token in example.text.split(whereSeparator: \.isWhitespace).dropFirst() {
                    words.insert(strip(token))
                }
            }
        }
        cachedMidSentenceWords = words
        return words
    }

    // MARK: Chinese

    /// Pinyin is written with spaces between words, so it says where to cut the characters:
    /// "Wǒ de fángjiān hěn xiǎo" → 我 | 的 | 房间 | 很 | 小.
    private static func chineseTiles(_ text: String, pinyin: String?) -> [SentenceTile]? {
        guard let pinyin else { return nil }
        let characters = Array(text.unicodeScalars
            .filter { !punctuation.contains($0) && !CharacterSet.whitespaces.contains($0) }
            .map(Character.init))
        let words = pinyin.split(whereSeparator: \.isWhitespace).map(strip).filter { !$0.isEmpty }

        var tiles: [SentenceTile] = []
        var index = 0
        for (offset, word) in words.enumerated() {
            let count = characterCount(forPinyin: word)
            guard count > 0, index + count <= characters.count else { return nil }
            var display = word
            if offset == 0 && !properNouns.contains(word) {
                display = word.prefix(1).lowercased() + word.dropFirst()
            }
            tiles.append(SentenceTile(id: offset, text: String(characters[index..<index + count]), pinyin: display))
            index += count
        }
        return index == characters.count ? tiles : nil
    }

    /// How many characters a pinyin word stands for: one per syllable, plus 儿 for a final -r
    /// (yìdiǎnr → 一点儿). Syllables are counted as runs of vowels, which works because pinyin
    /// marks the ambiguous joins with an apostrophe (Wǎn'ān).
    static func characterCount(forPinyin word: String) -> Int {
        var count = 0
        for part in word.split(separator: "'") {
            var inVowel = false
            for character in part {
                let vowel = isVowel(character)
                if vowel && !inVowel { count += 1 }
                inVowel = vowel
            }
        }
        // Erhua: a final -r after anything but the syllable "er" itself is an extra 儿
        // (yìdiǎnr, nàr, zhèr), while èr (二) and nǚ'ér are one syllable each.
        let letters = Array(word.lowercased())
        if letters.count >= 2, letters.last == "r" {
            let before = letters[letters.count - 2]
            if !isVowel(before) || baseLetter(before) != "e" {
                count += 1
            } else if letters.count >= 3, letters[letters.count - 3] != "'", !isVowel(letters[letters.count - 3]) {
                count += 1
            }
        }
        return count
    }

    /// The letter without its tone mark or umlaut: ǚ → u.
    private static func baseLetter(_ character: Character) -> Character {
        guard let scalar = String(character).decomposedStringWithCanonicalMapping.unicodeScalars.first else {
            return character
        }
        return Character(String(scalar).lowercased())
    }

    private static func isVowel(_ character: Character) -> Bool {
        "aeiou".contains(baseLetter(character))
    }
}
