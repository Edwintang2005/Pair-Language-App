import SwiftUI

struct OnboardingView: View {
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pair")
                        .font(.system(size: 48, weight: .bold))
                    Text("Teach each other your languages, five words at a time.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 16) {
                    step("1.circle.fill", "Each session, you each get five words: yours to learn, and your partner's to teach.")
                    step("2.circle.fill", "Teach your partner their words. The app gives you notes and examples.")
                    step("3.circle.fill", "Tap \u{201C}I've been taught this\u{201D} as you learn, then finish the session on both phones.")
                    step("4.circle.fill", "Review your words for a few minutes each day.")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Which language are you learning?")
                        .font(.headline)
                    ForEach(Language.allCases) { language in
                        Button {
                            progress.choose(learning: language)
                        } label: {
                            HStack {
                                Text(language.flag).font(.largeTitle)
                                VStack(alignment: .leading) {
                                    Text("I'm learning \(language.name)").font(.headline)
                                    Text("and teaching \(language.other.name)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Install Pair on both phones. Each of you picks the language you're learning.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}
