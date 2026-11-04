import Foundation

// Compiled into both the app and the widget extension.

/// One word as the widget shows it. The widget never reads the full word lists, only this.
struct WidgetWord: Codable, Hashable {
    let id: String
    /// As learners see it, e.g. "das Haus" or "房间".
    let headword: String
    /// Without the German article, for the small round widget.
    let shortWord: String
    let pinyin: String?
    let gloss: String
    let languageName: String
    /// Small line above the word on the rectangle: "das · noun", "verb" or the pinyin.
    /// Optional fields like these keep older widget.json files readable.
    var label: String? = nil
    /// Small line above the word on the round widget: the article or the pinyin.
    var circleLabel: String? = nil
    /// The line under the word on the rectangle: "house · die Häuser", "eyes · 一双眼睛".
    var detailLine: String? = nil
}

/// What the app hands to the widget, through the shared App Group container.
struct WidgetSnapshot: Codable, Equatable {
    var pinned: WidgetWord?
    /// Words to rotate through, one per day, when nothing is pinned.
    var pool: [WidgetWord] = []

    static let appGroup = "group.com.pairlanguage.app"
    static let widgetKind = "PairWordWidget"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "widget.json")
    }

    static func load() -> WidgetSnapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    func save() throws {
        guard let url = Self.fileURL else { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// The word to show on a given day: the pinned one, or the pool's word for that day.
    func word(for date: Date, calendar: Calendar = .current) -> WidgetWord? {
        if let pinned { return pinned }
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[day % pool.count]
    }
}
