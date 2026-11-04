import Foundation
import WidgetKit

/// Keeps the Lock Screen widget's copy of your words up to date.
enum WidgetSync {
    static func snapshot(for data: ProgressData, poolIDs: [String], content: ContentLibrary) -> WidgetSnapshot {
        WidgetSnapshot(
            pinned: data.pinnedWordID.flatMap { content.words[$0] }.map(widgetWord),
            pool: poolIDs.compactMap { content.words[$0] }.map(widgetWord)
        )
    }

    /// Writes the snapshot and asks the widget to redraw, but only when something changed:
    /// iOS limits how often a widget can be reloaded.
    static func update(progress: ProgressStore, content: ContentLibrary) {
        let snapshot = snapshot(for: progress.data, poolIDs: progress.widgetPoolIDs, content: content)
        guard snapshot != WidgetSnapshot.load() else { return }
        do {
            try snapshot.save()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
        } catch {
            print("Pair: couldn't update the widget: \(error)")
        }
    }

    static func widgetWord(_ word: Word) -> WidgetWord {
        var label: String?
        var circleLabel: String?
        var extra: String?
        if let noun = word.noun {
            label = "\(noun.article) · noun"
            circleLabel = noun.article
            extra = noun.plural.map { "die \($0)" }
        } else if word.language == .german {
            label = word.pos
            extra = word.verb.map { "er \($0.present3sg)" }
        } else {
            label = word.pinyin
            circleLabel = word.pinyin
            extra = MeasureWords.countingPhrase(for: word)?.text
        }
        // With an extra on the line, keep the meaning short so both fit.
        let detailLine = extra.map { "\(word.shortGloss) · \($0)" } ?? word.gloss

        return WidgetWord(
            id: word.id,
            headword: word.headword,
            shortWord: word.word,
            pinyin: word.pinyin,
            gloss: word.gloss,
            languageName: word.language.name,
            label: label,
            circleLabel: circleLabel,
            detailLine: detailLine
        )
    }
}
