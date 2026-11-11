import Foundation

/// The few settings Pair keeps in UserDefaults (via @AppStorage) rather than in progress.json.
/// Declared in PrivacyInfo.xcprivacy (CA92.1), and cleared by "Reset all progress".
enum AppSettings {
    /// "Check my speaking": run the offline speech check after a recording.
    static let checksSpeaking = "checksSpeaking"
    /// Build the sentence remembers Read or Listen mode.
    static let sentenceDrillListens = "sentenceDrillListens"

    static let allKeys = [checksSpeaking, sentenceDrillListens]
}
