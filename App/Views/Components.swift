import SwiftUI

extension View {
    /// The rounded "card" surface used throughout the app.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}

extension Color {
    /// Conventional learner colours for German genders: blue der, red die, green das.
    static func gender(_ gender: String) -> Color {
        switch gender {
        case "m": .blue
        case "f": .red
        default: .green
        }
    }
}

struct SpeakButton: View {
    let text: String
    let language: Language
    var size: Font = .title3

    var body: some View {
        Button {
            Speaker.shared.say(text, in: language)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(size)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Say \(text)")
    }
}

extension SpeakButton {
    init(word: Word, size: Font = .title3) {
        self.init(text: word.headword, language: word.language, size: size)
    }
}

/// The word as it should be shown: German nouns with a gender-coloured article,
/// Chinese with pinyin underneath.
struct HeadwordView: View {
    enum Style { case large, medium, flashcard }

    let word: Word
    var style: Style = .large
    var showsPinyin = true

    private var font: Font {
        switch style {
        case .large: word.language == .chinese ? .system(size: 40, weight: .semibold) : .system(size: 30, weight: .bold)
        case .medium: word.language == .chinese ? .system(size: 26, weight: .semibold) : .title3.weight(.semibold)
        case .flashcard: word.language == .chinese ? .system(size: 72, weight: .semibold) : .system(size: 44, weight: .bold)
        }
    }

    var body: some View {
        VStack(alignment: style == .flashcard ? .center : .leading, spacing: 2) {
            if let noun = word.noun {
                Text("\(Text(noun.article).foregroundStyle(Color.gender(noun.gender))) \(word.word)")
                    .font(font)
            } else {
                Text(word.word).font(font)
            }
            if showsPinyin, let pinyin = word.pinyin {
                Text(pinyin)
                    .font(style == .medium ? .subheadline : .title3)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ExampleView: View {
    let example: Example
    let language: Language

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(example.text).font(.body.weight(.medium))
                if let pinyin = example.pinyin {
                    Text(pinyin).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(example.english).font(.subheadline).foregroundStyle(.secondary).italic()
            }
            Spacer(minLength: 0)
            SpeakButton(text: example.text, language: language, size: .body)
        }
    }
}

struct StrengthBadge: View {
    let strength: Strength

    private var color: Color {
        switch strength {
        case .new: .orange
        case .learning: .blue
        case .strong: .green
        }
    }

    var body: some View {
        Text(strength.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}
