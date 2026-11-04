import SwiftUI

struct SettingsView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingReset = false
    @State private var confirmingSwitch = false

    var body: some View {
        NavigationStack {
            Form {
                if let learning = progress.learning {
                    Section {
                        LabeledContent("Learning", value: "\(learning.flag) \(learning.name)")
                        LabeledContent("Teaching", value: "\(learning.other.flag) \(learning.other.name)")
                        Button("Switch languages") { confirmingSwitch = true }
                    } header: {
                        Text("This phone")
                    }
                }

                Section {
                    Stepper(value: Binding(
                        get: { progress.currentSession },
                        set: { progress.setCurrentSession($0) }
                    ), in: 1...(content.sessionCount + 1)) {
                        LabeledContent("Current session", value: "\(progress.currentSession)")
                    }
                } header: {
                    Text("Keeping in step")
                } footer: {
                    Text("Both phones should show the same session. If one of you gets ahead, set this to match. Your review history isn't affected.")
                }

                Section("Progress") {
                    LabeledContent("Sessions finished", value: "\(progress.completedCount)")
                    LabeledContent("Words learned", value: "\(progress.learnedCount)")
                    LabeledContent("Strong words", value: "\(progress.strongCount())")
                    LabeledContent("Current streak", value: "\(progress.streak()) days")
                }

                Section {
                    Button("Reset all progress", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("Everything is stored only on this phone. There's no account and no server.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Switch languages?", isPresented: $confirmingSwitch, titleVisibility: .visible) {
                if let learning = progress.learning {
                    Button("Learn \(learning.other.name) instead") {
                        progress.choose(learning: learning.other)
                    }
                }
            } message: {
                Text("This phone will treat the other language as yours. Your session number and review history stay as they are.")
            }
            .confirmationDialog("Reset all progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) {
                    progress.resetAll()
                    dismiss()
                }
            } message: {
                Text("This deletes your sessions, streak and review history on this phone. It can't be undone.")
            }
        }
    }
}
