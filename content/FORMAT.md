# Word list data format

All content ships inside the app as JSON. There is no server and nothing is downloaded.

```
content/
  sessions.json    the shared curriculum: one entry per session, 5 German + 5 Chinese word IDs
  words-de.json    German words (learner: English speaker, teacher: German speaker)
  words-zh.json    Chinese words (learner: German speaker, teacher: Chinese speaker)
tools/
  validate.py      checks the three files are consistent
```

## How the app uses it (option 2: lockstep)

- You both work through the same session together. Session *N* gives one of you 5 German words and the
  other 5 Chinese words, and both sides share a **theme** so the conversation flows across languages.
- Each phone stores only a small amount of state: the current session number and per-word review history.
- Review history is keyed by **word ID**, never by position. That way sessions can be reordered or
  re-themed later without corrupting anyone's progress.
- Each session has 3 views: the **learner card** (the meaning is hidden until "I've been taught this"), the
  **teacher card** (everything, plus the `tip`), and the **review card** (used for spaced repetition).

## Rules

1. **IDs never change once the app ships.** They are `de-…` / `zh-…` followed by a readable slug.
   Homographs get a suffix (`zh-ta-he`, `zh-ta-she`).
2. Every session has **exactly 5** German and **exactly 5** Chinese IDs.
3. A word appears in **at most one** session.
4. Everything learner-facing is in English.
5. `tip` is written **for the teacher**: what to explain, demonstrate or watch out for.

## `sessions.json`

```jsonc
{
  "schemaVersion": 1,
  "sessions": [
    {
      "number": 1,                       // 1-based, contiguous
      "theme": "Greetings & manners",
      "conversationStarter": "Role-play …",  // a prompt for doing the session together
      "de": ["de-hallo", "…"],           // exactly 5
      "zh": ["zh-ni-hao", "…"]           // exactly 5
    }
  ]
}
```

## `words-de.json`

```jsonc
{
  "schemaVersion": 1,
  "language": "de",
  "speechLanguage": "de-DE",            // AVSpeechSynthesisVoice language code
  "words": [
    {
      "id": "de-haus",
      "word": "Haus",                   // headword without article; the app adds der/die/das from `noun.gender`
      "gloss": "house",
      "pos": "noun",                    // noun | verb | adjective | adverb | pronoun | interjection | phrase | particle
      "noun": { "gender": "n", "plural": "Häuser" },   // nouns only. gender: m | f | n. plural: null if (practically) none
      "verb": { "present3sg": "…", "participle": "…", "auxiliary": "haben" },  // verbs only. auxiliary: haben | sein
      "examples": [ { "text": "Das Haus ist groß.", "english": "The house is big." } ],
      "tip": "Two key phrases: nach Hause (going home) and zu Hause (at home)."
    }
  ]
}
```

## `words-zh.json`

```jsonc
{
  "schemaVersion": 1,
  "language": "zh",
  "script": "simplified",
  "speechLanguage": "zh-CN",
  "words": [
    {
      "id": "zh-fang-jian",
      "word": "房间",
      "pinyin": "fángjiān",              // tone marks; neutral tone has no mark (péngyou)
      "gloss": "room",
      "pos": "noun",
      "measureWord": { "word": "间", "pinyin": "jiān" },          // optional
      "characters": [                                            // optional, multi-character words only
        { "char": "房", "pinyin": "fáng", "meaning": "house, room" },
        { "char": "间", "pinyin": "jiān", "meaning": "space, room" }
      ],
      "examples": [ { "text": "我的房间很小。", "pinyin": "Wǒ de fángjiān hěn xiǎo.", "english": "My room is small." } ],
      "tip": "…"
    }
  ]
}
```

## Swift mapping (sketch)

```swift
struct Example: Codable { let text: String; let pinyin: String?; let english: String }

struct GermanNoun: Codable { let gender: String; let plural: String? }
struct GermanVerb: Codable { let present3sg: String; let participle: String; let auxiliary: String }
struct MeasureWord: Codable { let word: String; let pinyin: String }
struct CharacterPart: Codable { let char: String; let pinyin: String; let meaning: String }

struct Word: Codable, Identifiable {
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
    let characters: [CharacterPart]?
}
```

## Not covered yet

- **Frequency source.** Sessions 1–10 are hand-picked from very common words. Before drafting the rest, pick
  the source lists (e.g. DeReWo or the Leipzig corpora for German, SUBTLEX-CH or the HSK lists for Chinese),
  check their licences, and add an optional `frequencyRank` field.
- **Traditional characters.** These could be an optional `traditional` field if ever needed.
- **Audio.** On-device text-to-speech (AVSpeechSynthesizer) handles audio for now. A `recordings/` folder of
  your own voices could come later.
