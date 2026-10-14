import AppKit
import SwiftUI
import WhisperKit

@main
struct SwagTranscribeApp: App {
    init() {
        LaunchMode.start()
    }

    var body: some Scene {
        WindowGroup("swag-transcribe") { ContentView().background(SkinnedWindow()) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .defaultPosition(.center)
    }
}

/// Headless modes for development, next to the normal window:
///   --cli <audio> [--speakers]          transcribe and print text, SRT, decode stats and timings
///   --render icon|logo|ui|help|player <out.png>     render a view to PNG (build.sh uses `icon` for the app icon)
enum LaunchMode {
    @MainActor static func start() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render"), arguments.count > index + 2 {
            NSApplication.shared.setActivationPolicy(.prohibited)
            Task { @MainActor in
                render(arguments[index + 1], to: URL(fileURLWithPath: arguments[index + 2]))
                exit(0)
            }
        } else if let index = arguments.firstIndex(of: "--cli"), arguments.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let file = URL(fileURLWithPath: arguments[index + 1])
            Task { @MainActor in
                exit(await transcribe(file, speakers: arguments.contains("--speakers")) ? 0 : 1)
            }
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @MainActor private static func render(_ what: String, to url: URL) {
        let image: NSBitmapImageRep?
        switch what {
        case "icon": image = snapshot(AppIconView(), size: CGSize(width: 1024, height: 1024), scale: 1)
        case "logo": image = snapshot(LogoView(height: 200).padding(20), size: CGSize(width: 580, height: 240))
        case "help": image = snapshot(ContentView(showHelp: true), size: Skin.size)
        case "player":
            let sample = Transcriber()
            sample.text = localized(
                "Speaker 1: Morning! Shall we start with the new dashboard?\n\n"
                    + "Speaker 2: Yes. I moved the date picker to month to date, like we said.\n\n"
                    + "Speaker 3: Nice. Can we still go back 31 days for the daily revenue?\n\n"
                    + "Speaker 2: Sure, that is one click now.\n\nSpeaker 1: Perfect, then let's ship it on Friday.",
                "Spreker 1: Goedemorgen! Zullen we met het nieuwe dashboard beginnen?\n\n"
                    + "Spreker 2: Ja. Ik heb de datumkiezer op maand tot nu gezet, zoals afgesproken.\n\n"
                    + "Spreker 3: Mooi. Kunnen we voor de dagomzet nog steeds 31 dagen terug?\n\n"
                    + "Spreker 2: Zeker, dat is nu één klik.\n\nSpreker 1: Top, dan zetten we het vrijdag live.")
            let file = URL(fileURLWithPath: "/Users/you/Recordings/team-meeting.m4a")
            image = snapshot(ContentView(file: file, speakers: true, transcriber: sample), size: Skin.size)
        default: image = snapshot(ContentView(), size: Skin.size)
        }
        guard let png = image?.representation(using: .png, properties: [:]) else {
            print("render failed: \(what)")
            return
        }
        try? png.write(to: url)
    }

    /// Draws a view through AppKit in an offscreen window, so scroll views and native controls render too
    /// (SwiftUI's ImageRenderer leaves them blank).
    @MainActor private static func snapshot(_ view: some View, size: CGSize, scale: CGFloat = 2) -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))  // let SwiftUI lay out and draw once
        let pixels = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        guard let pixels else { return nil }
        pixels.size = size
        host.cacheDisplay(in: host.bounds, to: pixels)
        return pixels
    }

    @MainActor private static func transcribe(_ file: URL, speakers: Bool) async -> Bool {
        let transcriber = Transcriber()
        transcriber.run(
            file, language: Tuning.language ?? "auto", model: Tuning.model ?? WhisperModel.turbo.rawValue,
            speakers: speakers)
        let start = Date()
        var last = ""
        while transcriber.running {
            let left = transcriber.expectedFinish.map { " left=" + formatDuration($0.timeIntervalSinceNow) } ?? ""
            let now = transcriber.status + (transcriber.progress.map { " \(Int($0 * 100))%" } ?? "") + left
            if now != last {
                print(String(format: "%5.1fs ", Date().timeIntervalSince(start)) + now)
                last = now
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        print(transcriber.error ?? transcriber.text)
        print("---")
        print(transcriber.srt)
        printStats(transcriber.segmentStats)
        printTimings(transcriber.timings)
        return transcriber.error == nil
    }

    private static func printStats(_ stats: [SegmentStats]) {
        guard !stats.isEmpty else { return }
        for (temperature, count) in Dictionary(grouping: stats, by: \.temperature).mapValues(\.count).sorted(by: {
            $0.key < $1.key
        }) {
            print("SEGSTATS temperature", temperature, "segments", count)
        }
        let logprobs = stats.map(\.avgLogprob).sorted()
        let ratios = stats.map(\.compressionRatio).sorted()
        print(
            "SEGSTATS avgLogprob p10/p50/p90", logprobs[logprobs.count / 10], logprobs[logprobs.count / 2],
            logprobs[logprobs.count * 9 / 10])
        print(
            "SEGSTATS compressionRatio p50/p90/max", ratios[ratios.count / 2], ratios[ratios.count * 9 / 10],
            ratios[ratios.count - 1])
        let repetitive = stats.filter { $0.compressionRatio > 2.0 }.count
        let unsure = stats.filter { $0.avgLogprob < -1.5 }.count
        print("SEGSTATS suspect: ratio>2.0", repetitive, "logprob<-1.5", unsure, "of", stats.count)
    }

    /// Where the time goes inside WhisperKit, summed over chunks.
    private static func printTimings(_ timings: [TranscriptionTimings]) {
        guard !timings.isEmpty else { return }
        let rows: [(String, KeyPath<TranscriptionTimings, Double>)] = [
            ("modelLoading(once)", \.modelLoading), ("prewarm(once)", \.prewarmLoadTime),
            ("audioLoading", \.audioLoading),
            ("logmels", \.logmels), ("encoding", \.encoding), ("decodingLoop", \.decodingLoop),
            ("  predictions", \.decodingPredictions), ("  kvCaching", \.decodingKvCaching),
            ("  sampling", \.decodingSampling),
            ("  fallback", \.decodingFallback), ("encodingRuns", \.totalEncodingRuns),
            ("decodingLoops(tokens)", \.totalDecodingLoops), ("fallbacks", \.totalDecodingFallbacks),
            ("windows", \.totalDecodingWindows),
        ]
        print("TIMINGS chunks=\(timings.count) wall=\(String(format: "%.1f", timings.map(\.fullPipeline).max() ?? 0))")
        for (name, key) in rows {
            print("TIMINGS", name, String(format: "%.2f", timings.reduce(0) { $0 + $1[keyPath: key] }))
        }
    }
}
