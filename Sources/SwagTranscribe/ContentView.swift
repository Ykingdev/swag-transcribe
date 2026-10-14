import AVFoundation
import AppKit
import SwiftUI

/// The player: side buttons on the left wing, LCD screen with transcript and settings, transport controls in the pod.
struct ContentView: View {
    private enum ResultTab { case transcript, srt }

    private static let languages = [
        ("auto", "AUTO"), ("nl", localized("DUTCH", "NEDERLANDS")), ("en", localized("ENGLISH", "ENGELS")),
        ("de", localized("GERMAN", "DUITS")), ("fr", localized("FRENCH", "FRANS")),
        ("es", localized("SPANISH", "SPAANS")),
    ]

    @StateObject private var transcriber = Transcriber()
    @StateObject private var live = LiveTranscriber()
    @State private var file: URL?
    @State private var language = "auto"
    @State private var model = WhisperModel.turbo
    @State private var speakers = false
    @State private var picking = false
    @State private var tab = ResultTab.transcript
    @State private var showHelp: Bool
    /// Length of the chosen file, for the time estimate.
    @State private var audioSeconds: Double?

    init(showHelp: Bool = false) {
        _showHelp = State(initialValue: showHelp)
    }

    private var shown: String {
        switch tab {
        case .srt: transcriber.srt
        case .transcript: transcriber.text.isEmpty ? live.text : transcriber.text
        }
    }

    private var status: String {
        if live.running { return localized("LISTENING…", "LUISTERT…") }
        if transcriber.running { return transcriber.status.uppercased() }
        if transcriber.error != nil || live.error != nil { return localized("ERROR", "FOUT") }
        return transcriber.srt.isEmpty ? localized("READY FOR AUDIO", "KLAAR VOOR AUDIO") : localized("DONE", "KLAAR")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChassisView().dragsWindow()
            titleStrip.placed(CGRect(x: 262, y: 30, width: 690, height: 44))
            screen.placed(CGRect(x: 262, y: 84, width: 690, height: 410))
            sideButtons.placed(CGRect(x: 42, y: 130, width: 178, height: 372))
            controlPod.placed(CGRect(x: 280, y: 520, width: 460, height: 140))
        }
        .frame(width: Skin.size.width, height: Skin.size.height)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .movie]) { file = try? $0.get() }
        .task(id: file) {
            audioSeconds = nil
            guard let file else { return }
            audioSeconds = try? await AVURLAsset(url: file).load(.duration).seconds
        }
        .dropDestination(for: URL.self) { urls, _ in
            file = urls.first
            return true
        }
    }

    // MARK: Title strip

    private var titleStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 15, weight: .heavy)).foregroundStyle(Brand.purple)
            Text("swag-transcribe")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(Skin.rim)
            Spacer()
            windowButton("questionmark", tint: showHelp ? Brand.purple : Brand.lilac) { showHelp.toggle() }
                .help(localized("How it works", "Zo werkt het"))
            windowButton("minus") { NSApp.keyWindow?.miniaturize(nil) }
            windowButton("xmark") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.98), Color(white: 0.72)], startPoint: .top, endPoint: .bottom)
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Skin.rim, lineWidth: 2.5))
                .dragsWindow()
        }
    }

    private func windowButton(_ symbol: String, tint: Color = Brand.pink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .black))
        }
        .buttonStyle(GlossyButtonStyle(form: .circle, tint: tint))
        .frame(width: 26, height: 26)
    }

    // MARK: Screen

    private var screen: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                LogoView(height: 78)
                VStack(alignment: .leading, spacing: 6) {
                    LCDText(file?.lastPathComponent.uppercased() ?? localized("NO FILE", "GEEN BESTAND"), size: 17)
                        .lineLimit(1)
                    LCDText(
                        file?.deletingLastPathComponent().path
                            ?? localized("DROP AUDIO OR VIDEO HERE", "SLEEP AUDIO OF VIDEO HIERHEEN"), size: 11,
                        color: Skin.lcdDim
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    waitLine
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            separator
            if showHelp {
                HelpView()
            } else {
                HStack(spacing: 0) {
                    transcript
                    Rectangle().fill(Skin.bezel).frame(width: 2)
                    infoPanel.frame(width: 200)
                }
            }
            separator
            statusStrip
        }
        .background(Skin.screen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Skin.bezel, lineWidth: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Skin.rim, lineWidth: 2).padding(-2))
    }

    private var separator: some View {
        Rectangle().fill(Skin.bezel).frame(height: 2)
    }

    @ViewBuilder private var transcript: some View {
        if tab == .transcript, let messages = chatMessages(in: shown, name: localized("Speaker", "Spreker")) {
            ChatTranscript(messages: messages).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Group {
                    if shown.isEmpty {
                        Text(localized("> waiting for audio_", "> wacht op audio_")).foregroundStyle(Skin.lcdDim)
                    } else {
                        // White text so every speaker color, lime included, stands out.
                        Text(SpeakerColors.highlight(shown, base: tab == .srt ? .white.opacity(0.8) : .white))
                    }
                }
                .font(.system(size: 13, weight: tab == .srt ? .regular : .medium, design: .monospaced))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            setting(
                localized("LANGUAGE", "TAAL"), Self.languages.first { $0.0 == language }?.1 ?? language,
                action: nextLanguage)
            setting("MODEL", model.label.uppercased(), action: nextModel)
            setting(localized("SPEAKERS", "SPREKERS"), speakers ? localized("ON", "AAN") : localized("OFF", "UIT")) {
                speakers.toggle()
            }
            VStack(alignment: .leading, spacing: 3) {
                LCDText(localized("COMPUTE", "REKENPAD"), size: 10, color: Skin.lcdDim)
                LCDText(transcriber.computeName.isEmpty ? "AUTO" : transcriber.computeName.uppercased(), size: 12)
            }
            Spacer(minLength: 0)
            if let error = transcriber.error ?? live.error {
                Text(error)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Brand.pink)
                    .textSelection(.enabled)
            } else {
                LCDText(localized("CLICK TO CHANGE", "KLIK OM TE WISSELEN"), size: 9, color: Skin.lcdDim)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func setting(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                LCDText(title, size: 10, color: Skin.lcdDim)
                LCDText("▸ \(value)", size: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(transcriber.running)
    }

    /// Before a run: audio length and the expected time. During a run: things to do while waiting.
    @ViewBuilder private var waitLine: some View {
        if transcriber.running, let finish = transcriber.expectedFinish {
            let ideas = waitingIdeas(for: finish.timeIntervalSinceNow)
            Marquee(
                messages: ideas.map {
                    "★ " + localized("WHILE YOU WAIT: ", "TERWIJL JE WACHT: ") + $0.uppercased() + " ★"
                })
        } else if !transcriber.running, let audioSeconds {
            let estimate = audioSeconds * Throughput.ratio(model: model.rawValue, speakers: speakers)
            LCDText(
                "\(formatDuration(audioSeconds)) AUDIO · "
                    + localized(
                        "≈ \(formatDuration(estimate)) TO TRANSCRIBE", "≈ \(formatDuration(estimate)) TRANSCRIBEREN"),
                size: 12, color: Brand.pink)
        }
    }

    private var statusStrip: some View {
        VStack(spacing: 8) {
            LCDProgress(
                value: transcriber.running ? transcriber.progress : nil, active: transcriber.running || live.running)
            HStack {
                LCDText("STATUS: \(status)", size: 13).lineLimit(1)
                Spacer()
                if transcriber.running {
                    remaining
                } else if live.running {
                    LCDText("● REC", size: 13, color: Brand.pink)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// "42% · ≈ 1:20 LEFT", ticking every second.
    private var remaining: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let percent = transcriber.progress.map { "\(Int($0 * 100))%" }
            let left = transcriber.expectedFinish.map { finish in
                let seconds = finish.timeIntervalSince(context.date)
                guard seconds >= 1 else { return localized("ALMOST DONE", "BIJNA KLAAR") }
                return localized("≈ \(formatDuration(seconds)) LEFT", "NOG ≈ \(formatDuration(seconds))")
            }
            LCDText([percent, left].compactMap { $0 }.joined(separator: " · "), size: 14)
        }
    }

    // MARK: Side buttons

    private var sideButtons: some View {
        VStack(spacing: 14) {
            sideButton(localized("File", "Bestand"), "folder.fill") { picking = true }
                .disabled(transcriber.running)
            sideButton(live.running ? "Stop live" : "Live", "mic.fill", lit: live.running, action: toggleLive)
                .disabled(transcriber.running)
            sideButton(localized("Speakers", "Sprekers"), "person.2.fill", lit: speakers) { speakers.toggle() }
                .disabled(transcriber.running)
            sideButton(localized("Copy", "Kopieer"), "doc.on.doc.fill", action: copy)
                .disabled(shown.isEmpty)
            sideButton(localized("Save", "Bewaar"), "square.and.arrow.down.fill", action: save)
                .disabled(shown.isEmpty)
        }
    }

    private func sideButton(_ title: String, _ symbol: String, lit: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(GlossyButtonStyle(form: .rounded, tint: Brand.purple, lit: lit))
        .frame(height: 60)
    }

    // MARK: Control pod

    private var controlPod: some View {
        HStack(spacing: 22) {
            Button(action: toggleTranscription) {
                Image(systemName: transcriber.running ? "stop.fill" : "play.fill")
                    .font(.system(size: 38, weight: .black))
                    .offset(x: transcriber.running ? 0 : 3)
            }
            .buttonStyle(GlossyButtonStyle(form: .circle, tint: transcriber.running ? Brand.pink : Brand.purple))
            .frame(width: 104, height: 104)
            .disabled(file == nil || live.running)
            .keyboardShortcut(.defaultAction)
            .help(transcriber.running ? "Stop" : localized("Transcribe", "Transcriberen"))

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    tabButton(localized("TEXT", "TEKST"), .transcript)
                    tabButton("SRT", .srt)
                }
                Text(
                    transcriber.running
                        ? localized("TRANSCRIBING", "BEZIG MET TRANSCRIBEREN")
                        : (file == nil
                            ? localized("CHOOSE A FILE FIRST", "KIES EERST EEN BESTAND")
                            : localized("PRESS PLAY", "DRUK OP PLAY"))
                )
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: Skin.rim, radius: 0, y: 1)
            }
        }
    }

    private func tabButton(_ title: String, _ value: ResultTab) -> some View {
        Button(title) { tab = value }
            .buttonStyle(
                GlossyButtonStyle(form: .pill, tint: tab == value ? Brand.purple : Brand.lilac, lit: tab == value)
            )
            .frame(width: 120, height: 40)
    }

    // MARK: Actions

    private func toggleTranscription() {
        if transcriber.running {
            transcriber.stop()
        } else if let file {
            tab = .transcript
            showHelp = false
            transcriber.run(file, language: language, model: model.rawValue, speakers: speakers)
        }
    }

    private func toggleLive() {
        if !live.running {
            transcriber.text = ""
            transcriber.srt = ""
            tab = .transcript
        }
        live.toggle(language: language)
    }

    private func nextLanguage() {
        let codes = Self.languages.map(\.0)
        language = codes[((codes.firstIndex(of: language) ?? 0) + 1) % codes.count]
    }

    private func nextModel() {
        let all = WhisperModel.allCases
        model = all[((all.firstIndex(of: model) ?? 0) + 1) % all.count]
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shown, forType: .string)
    }

    private func save() {
        let panel = NSSavePanel()
        let name = file?.deletingPathExtension().lastPathComponent ?? "transcript"
        panel.nameFieldStringValue = name + (tab == .srt ? ".srt" : ".txt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try shown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
