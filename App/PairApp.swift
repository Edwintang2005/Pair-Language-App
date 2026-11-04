import SwiftUI

@main
struct PairApp: App {
    @State private var progress = ProgressStore.live()
    private let content: ContentLibrary

    init() {
        do {
            content = try ContentLibrary.loadBundled()
        } catch {
            // The word lists ship inside the app, so this only happens if the build is broken.
            fatalError("Could not load bundled content: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(progress)
                .environment(content)
        }
    }
}

struct RootView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content

    var body: some View {
        if let learning = progress.learning {
            TabView {
                TodayView(learning: learning)
                    .tabItem { Label("Today", systemImage: "sun.max") }
                ReviewView()
                    .tabItem { Label("Review", systemImage: "rectangle.on.rectangle.angled") }
                    .badge(progress.dueWordIDs().count)
                LibraryView(learning: learning)
                    .tabItem { Label("Words", systemImage: "books.vertical") }
            }
        } else {
            OnboardingView()
        }
    }
}
