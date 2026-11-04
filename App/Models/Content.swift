import Foundation
import Observation

/// The two languages in the app. Each phone is set to the one its owner is *learning*;
/// the other one is the language they teach.
enum Language: String, Codable, CaseIterable, Identifiable {
    case german = "de"
    case chinese = "zh"

    var id: String { rawValue }
    var name: String { self == .german ? "German" : "Chinese" }
    var flag: String { self == .german ? "🇩🇪" : "🇨🇳" }
    var speechCode: String { self == .german ? "de-DE" : "zh-CN" }
    var other: Language { self == .german ? .chinese : .german }
}

struct Example: Codable, Hashable {
    let text: String
    let pinyin: String?
    let english: String
}

struct GermanNoun: Codable, Hashable {
    /// "m", "f" or "n"
    let gender: String
    let plural: String?
    /// A rule that explains the gender when the word's ending doesn't. See `GenderHints`.
    let hint: String?

    var article: String {
        switch gender {
        case "m": "der"
        case "f": "die"
        default: "das"
        }
    }
}

struct GermanVerb: Codable, Hashable {
    let present3sg: String
    let participle: String
    /// "haben" or "sein"
    let auxiliary: String
}

struct MeasureWord: Codable, Hashable {
    let word: String
    let pinyin: String
    /// Other measure words that are fine too, so the drill never marks them wrong.
    let also: [String]?
}

struct CharacterPart: Codable, Hashable {
    let char: String
    let pinyin: String
    let meaning: String
}

/// One word, in either language. See content/FORMAT.md.
struct Word: Codable, Hashable, Identifiable {
    let id: String
    let word: String
    let gloss: String
    let pos: String
    let examples: [Example]
    let tip: String
    // German only
    let noun: GermanNoun?
    let verb: GermanVerb?
    // Chinese only
    let pinyin: String?
    let measureWord: MeasureWord?
    /// For Chinese nouns without a measure word: "direct" (三天) or "none" (not counted, like 今天).
    let counting: String?
    let characters: [CharacterPart]?

    var language: Language { id.hasPrefix("zh-") ? .chinese : .german }

    /// What the learner sees and hears: German nouns carry their article ("das Haus").
    var headword: String {
        if let noun { "\(noun.article) \(word)" } else { word }
    }

    /// A one-line grammar summary, if the word has one worth showing.
    var grammarLine: String? {
        if let noun {
            if let plural = noun.plural { return "plural: die \(plural)" }
            return "usually no plural"
        }
        if let verb {
            let aux = verb.auxiliary == "sein" ? "ist" : "hat"
            return "er \(verb.present3sg) · \(aux) \(verb.participle)"
        }
        if let measureWord {
            return "measure word: \(measureWord.word) (\(measureWord.pinyin))"
        }
        if countsDirectly {
            return "no measure word: \(MeasureWords.countingPhrase(for: self)?.text ?? word)"
        }
        return nil
    }

    /// Chinese nouns counted with no measure word in between: 三天, 两年.
    var countsDirectly: Bool { counting == "direct" }

    /// The English meaning up to the first comma or semicolon: "car" from "car, vehicle".
    var shortGloss: String {
        String(gloss.split(whereSeparator: { $0 == "," || $0 == ";" }).first ?? Substring(gloss))
            .trimmingCharacters(in: .whitespaces)
    }

    var partOfSpeech: String { pos.prefix(1).uppercased() + pos.dropFirst() }

    /// Matches the search text against the word, its pinyin and its meaning.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let haystack = [word, headword, gloss, pinyin ?? ""]
        return haystack.contains { $0.localizedStandardContains(q) }
    }
}

struct Session: Codable, Hashable, Identifiable {
    let number: Int
    let theme: String
    let conversationStarter: String
    let de: [String]
    let zh: [String]

    var id: Int { number }

    func wordIDs(for language: Language) -> [String] {
        language == .german ? de : zh
    }
}

enum ContentError: Error, CustomStringConvertible {
    case missingFile(String)

    var description: String {
        switch self {
        case .missingFile(let name): "\(name).json is missing from the app bundle"
        }
    }
}

/// The bundled curriculum. Read-only for the life of the app.
@Observable
final class ContentLibrary {
    let sessions: [Session]
    let words: [String: Word]

    init(sessions: [Session], words: [Word]) {
        self.sessions = sessions.sorted { $0.number < $1.number }
        self.words = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var sessionCount: Int { sessions.count }

    func session(_ number: Int) -> Session? {
        sessions.first { $0.number == number }
    }

    func words(in session: Session, language: Language) -> [Word] {
        session.wordIDs(for: language).compactMap { words[$0] }
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> ContentLibrary {
        struct SessionsFile: Decodable { let sessions: [Session] }
        struct WordsFile: Decodable { let words: [Word] }

        func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw ContentError.missingFile(name)
            }
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }

        let sessions = try load("sessions", as: SessionsFile.self).sessions
        let german = try load("words-de", as: WordsFile.self).words
        let chinese = try load("words-zh", as: WordsFile.self).words
        return ContentLibrary(sessions: sessions, words: german + chinese)
    }
}
