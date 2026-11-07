import SwiftUI

/// "Copy what you hear": play a sentence, say it, then hear the original and yourself back to back.
/// Not marked: you're the judge. The optional speech check shows which words your iPhone understood.
struct SpeakingDrillView: View {
    let language: Language
    let wordIDs: [String]

    @Environment(ContentLibrary.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [SpeakingItem] = []
    @State private var total = 0
    @State private var started = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let item = queue.first {
                    VStack(spacing: 16) {
                        RoundProgress(done: total - queue.count, total: total)
                        SpeakingCard(item: item, nextTitle: queue.count > 1 ? "Next" : "Finish") { next(after: item.id) }
                            .id(item.id)
                    }
                    .padding(16)
                } else if started {
                    finished
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Speaking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if !started {
                queue = SpeakingItem.items(wordIDs: wordIDs, content: content)
                total = queue.count
                started = true
            }
        }
        .onDisappear { AudioSession.usePlayback() }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Nicely done").font(.title.bold())
            Text("You practised \(total) sentence\(total == 1 ? "" : "s") out loud.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private func next(after id: UUID) {
        guard queue.first?.id == id else { return }
        withAnimation(.snappy) { _ = queue.removeFirst() }
    }
}

/// One sentence to copy: the sentence, play buttons, the record button, then the comparison and
/// (if it's on and the iPhone can do it offline) which words the speech check understood.
struct SpeakingCard: View {
    let item: SpeakingItem
    let nextTitle: String
    let onNext: () -> Void

    @AppStorage("checksSpeaking") private var checksSpeaking = true
    @Environment(\.openURL) private var openURL

    @State private var recorder = VoiceRecorder()
    @State private var check: SpeechCheck.Outcome?
    @State private var checking = false
    @State private var micDenied = false
    @State private var attempts = 0

    private var language: Language { item.word.language }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sentence
                    if recorder.recording != nil || checking {
                        Divider()
                        result
                    }
                    if micDenied {
                        micDeniedNote
                    }
                }
                .card(padding: 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            recordButton

            Button {
                recorder.discard()
                onNext()
            } label: {
                Text(attempts == 0 ? "Skip" : nextTitle)
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .task {
            // Hear it first.
            try? await Task.sleep(for: .seconds(0.3))
            Speaker.shared.say(item.example.text, in: language)
        }
        .onDisappear { recorder.discard() }
    }

    // MARK: The sentence

    private var sentence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listen, then say it")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.example.text)
                    .font(language == .chinese ? .title.weight(.medium) : .title2.weight(.semibold))
                if let pinyin = item.example.pinyin {
                    Text(pinyin).font(.title3).foregroundStyle(.secondary)
                }
                Text(item.example.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            HStack(spacing: 10) {
                Button {
                    recorder.stopPlaying()
                    Speaker.shared.say(item.example.text, in: language)
                } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                }
                Button {
                    recorder.stopPlaying()
                    Speaker.shared.say(item.example.text, in: language, slow: true)
                } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(recorder.state == .recording)
        }
    }

    // MARK: Recording

    private var recordButton: some View {
        let recording = recorder.state == .recording
        return VStack(spacing: 8) {
            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(recording ? Color.red : Color.accentColor)
                        .frame(width: 84, height: 84)
                    Image(systemName: recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: (recording ? Color.red : Color.accentColor).opacity(0.35), radius: recording ? 14 : 6)
                .animation(.snappy, value: recording)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recording ? "Stop recording" : "Record yourself")
            Text(recording ? "Recording… tap to stop" : (attempts == 0 ? "Tap and say it" : "Tap to try again"))
                .font(.subheadline)
                .foregroundStyle(recording ? .red : .secondary)
        }
    }

    private func toggleRecording() async {
        if recorder.state == .recording {
            recorder.stop()
            attempts += 1
            await afterRecording()
            return
        }
        guard await VoiceRecorder.requestPermission() else {
            withAnimation { micDenied = true }
            return
        }
        micDenied = false
        check = nil
        recorder.start()
    }

    /// The comparison straight away, with the speech check running alongside.
    private func afterRecording() async {
        guard let url = recorder.recording else { return }
        let locale = language.speechCode
        let checkTask: Task<SpeechCheck.Outcome, Never>? = checksSpeaking
            ? Task.detached { await SpeechCheck.check(url, locale: locale) }
            : nil
        if checkTask != nil { checking = true }
        await recorder.compare(with: item.example.text, in: language)
        let result = await checkTask?.value
        guard recorder.recording == url else { return }  // re-recorded in the meantime
        withAnimation(.snappy) {
            check = result
            checking = false
        }
    }

    // MARK: Result

    @ViewBuilder
    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    Task { await recorder.compare(with: item.example.text, in: language) }
                } label: {
                    Label("Compare", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await recorder.playRecording() }
                } label: {
                    Label("Just mine", systemImage: "person.wave.2.fill")
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
            .disabled(recorder.isPlaying || recorder.state == .recording)

            Text("Compare plays the original, then you.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if checking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Listening for the words…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let check {
                checkResult(check)
            }
        }
    }

    @ViewBuilder
    private func checkResult(_ outcome: SpeechCheck.Outcome) -> some View {
        switch outcome {
        case .heard(let transcript):
            let heard = SpeechMatch.heard(item.words.map(\.text), in: transcript, language: language)
            let count = heard.filter { $0 }.count
            VStack(alignment: .leading, spacing: 10) {
                Label(summary(count: count, of: heard.count),
                      systemImage: count == heard.count ? "checkmark.circle.fill" : "ear")
                    .font(.headline)
                    .foregroundStyle(count == heard.count ? .green : .primary)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(item.words.enumerated()), id: \.offset) { index, word in
                        Text(word.text)
                            .font(.title3.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(heard[index] ? Color.green : Color.secondary)
                            .background((heard[index] ? Color.green : Color.gray).opacity(0.15),
                                        in: .rect(cornerRadius: 8))
                    }
                }
                Text("It heard: \(transcript)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .nothing:
            Label("It didn't catch anything. Try again a little closer to the phone.", systemImage: "ear.trianglebadge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("Checking isn't available on this iPhone for \(language.name), so trust your ears: compare the two.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func summary(count: Int, of total: Int) -> String {
        if count == total { return "It understood every word" }
        if count == 0 { return "It didn't pick out the words yet" }
        return "It understood \(count) of \(total) words"
    }

    private var micDeniedNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pair needs the microphone to record you. Recordings stay on your phone.")
                .font(.subheadline)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}
