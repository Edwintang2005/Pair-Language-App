import SwiftUI
import WidgetKit

@main
struct PairWidgetBundle: WidgetBundle {
    var body: some Widget {
        PairWordWidget()
    }
}

struct PairWordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: WordProvider()) { entry in
            PairWidgetView(entry: entry)
        }
        .configurationDisplayName("Pair word")
        .description("Glance at one of your words. Pin one in the app, or get a new one each day.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall])
    }
}

// MARK: Timeline

struct WordEntry: TimelineEntry {
    let date: Date
    let word: WidgetWord?
    let isPinned: Bool
}

struct WordProvider: TimelineProvider {
    func placeholder(in context: Context) -> WordEntry {
        WordEntry(date: .now, word: .sample, isPinned: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WordEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        // In the widget gallery, show a sample if there's nothing real yet.
        if context.isPreview && snapshot.word(for: .now) == nil {
            completion(placeholder(in: context))
        } else {
            completion(entry(for: .now, from: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()

        // A pinned word (or a single word) never changes by itself; the app reloads us when it does.
        guard snapshot.pinned == nil, snapshot.pool.count > 1 else {
            completion(Timeline(entries: [entry(for: .now, from: snapshot)], policy: .never))
            return
        }

        // Otherwise, a new word at each midnight for the next week.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [entry(for: .now, from: snapshot)]
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(entry(for: day, from: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date, from snapshot: WidgetSnapshot) -> WordEntry {
        WordEntry(date: date, word: snapshot.word(for: date), isPinned: snapshot.pinned != nil)
    }
}

extension WidgetWord {
    static let sample = WidgetWord(
        id: "sample", headword: "das Haus", shortWord: "Haus", pinyin: nil,
        gloss: "house", languageName: "German"
    )
}

// MARK: Views

struct PairWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WordEntry

    var body: some View {
        Group {
            if let word = entry.word {
                switch family {
                case .accessoryInline: inline(word)
                case .accessoryCircular: circular(word)
                case .accessoryRectangular: rectangular(word)
                default: small(word)
                }
            } else {
                empty
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.42, blue: 0.92), Color(red: 0.17, green: 0.21, blue: 0.57)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                Color.clear
            }
        }
    }

    private func inline(_ word: WidgetWord) -> some View {
        Text("\(word.headword) · \(word.gloss)")
    }

    private func circular(_ word: WidgetWord) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            Text(word.shortWord)
                .font(.system(size: 22, weight: .semibold))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(6)
                .widgetAccentable()
        }
    }

    private func rectangular(_ word: WidgetWord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(word.headword)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            if let pinyin = word.pinyin {
                Text(pinyin).font(.caption)
            }
            Text(word.gloss)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(word.pinyin == nil ? 2 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ word: WidgetWord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(word.languageName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .opacity(0.8)
                Spacer()
                if entry.isPinned {
                    Image(systemName: "pin.fill").font(.caption2)
                }
            }
            Spacer(minLength: 0)
            Text(word.headword)
                .font(.title2.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            if let pinyin = word.pinyin {
                Text(pinyin).font(.subheadline).opacity(0.85)
            }
            Text(word.gloss)
                .font(.subheadline)
                .lineLimit(2)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryInline:
            Text("Pair: no words yet")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "character.bubble")
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("Pair").font(.headline)
                Text("Your words appear here once you've been taught some.")
                    .font(.caption)
                    .lineLimit(3)
            }
            .foregroundStyle(family == .systemSmall ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
