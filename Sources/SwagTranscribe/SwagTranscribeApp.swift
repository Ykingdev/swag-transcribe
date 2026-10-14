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
///   --render icon|logo|ui|help <out.png>     render a view to PNG (build.sh uses `icon` for the app icon)
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
        let renderer: ImageRenderer<AnyView>
        switch what {
        case "icon": renderer = ImageRenderer(content: AnyView(AppIconView()))
        case "logo": renderer = ImageRenderer(content: AnyView(LogoView(height: 200).padding(20)))
        case "help":
            renderer = ImageRenderer(
                content: AnyView(HelpView(scrolls: false).frame(width: 686).background(Skin.screen)))
        default: renderer = ImageRenderer(content: AnyView(ContentView()))
        }
        renderer.scale = what == "icon" ? 1 : 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            print("render failed: \(what)")
            return
        }
        try? png.write(to: url)
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
