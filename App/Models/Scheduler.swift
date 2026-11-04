import Foundation

/// Review state for one learned word.
struct ReviewState: Codable, Hashable {
    /// 1 = newest. Each box doubles the gap before the next review.
    var box: Int
    /// The start of the day the word is next due.
    var due: Date
    var lastReviewed: Date?
    var reviewCount: Int = 0
}

enum ReviewGrade: CaseIterable {
    case again, good, easy

    var title: String {
        switch self {
        case .again: "Again"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

enum Strength: String {
    case new = "New"
    case learning = "Learning"
    case strong = "Strong"
}

/// A simple Leitner-style spaced-repetition schedule. Words move up a box when
/// remembered and back to box 1 when forgotten; due dates fall on day boundaries.
enum Scheduler {
    /// Days until the next review, per box.
    static let intervals = [1, 2, 4, 8, 16, 32, 64, 128]
    static var maxBox: Int { intervals.count }

    static func newCard(learnedOn now: Date, calendar: Calendar = .current) -> ReviewState {
        ReviewState(box: 1, due: dueDate(box: 1, from: now, calendar: calendar))
    }

    static func review(_ state: ReviewState, grade: ReviewGrade, now: Date,
                       calendar: Calendar = .current) -> ReviewState {
        let box = switch grade {
        case .again: 1
        case .good: min(state.box + 1, maxBox)
        case .easy: min(state.box + 2, maxBox)
        }
        return ReviewState(
            box: box,
            due: dueDate(box: box, from: now, calendar: calendar),
            lastReviewed: now,
            reviewCount: state.reviewCount + 1
        )
    }

    /// Days until the next review if `state` is graded `grade`. Used to label the buttons.
    static func days(after state: ReviewState, grade: ReviewGrade) -> Int {
        let box = review(state, grade: grade, now: .now).box
        return intervals[box - 1]
    }

    static func strength(of state: ReviewState) -> Strength {
        switch state.box {
        case ...2: .new
        case 3...4: .learning
        default: .strong
        }
    }

    private static func dueDate(box: Int, from now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: intervals[box - 1], to: today) ?? today
    }
}
