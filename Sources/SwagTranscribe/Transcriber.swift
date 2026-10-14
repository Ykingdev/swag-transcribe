import AVFoundation
import FluidAudio
import Foundation
import WhisperKit

enum TranscriptionError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): localized("File not found: \(path)", "Bestand niet gevonden: \(path)")
        }
    }
}

/// Decode statistics of one Whisper segment, printed by `--cli` to tune thresholds.
struct SegmentStats {
    let temperature: Float
    let avgLogprob: Float
    let compressionRatio: Float
}

/// File transcription: optional speaker diarization (FluidAudio), then Whisper (WhisperKit), as text and SRT.
@MainActor final class Transcriber: ObservableObject {
    @Published var running = false
    @Published var progress: Double?
    @Published var status = ""
    @Published var text = ""
    @Published var srt = ""
    @Published var error: String?
    @Published private(set) var computeName = ""
    /// When the running transcription should be done: first from `Throughput`, then from the actual progress.
    @Published private(set) var expectedFinish: Date?

    /// Per-chunk timings and per-segment stats of the last run, for the `--cli` breakdown.
    private(set) var timings: [TranscriptionTimings] = []
    private(set) var segmentStats: [SegmentStats] = []

    private var pipelines: [WhisperKit] = []
    private var loadedModel = ""
    private var loadedPath: ComputePath?
    private var diarizer: DiarizerManager?
    private var task: Task<Void, Never>?

    func stop() { task?.cancel() }

    func run(_ file: URL, language: String, model: String, speakers: Bool) {
        running = true
        progress = nil
        text = ""
        srt = ""
        error = nil
        task = Task {
            do {
                try await transcribe(file, language: language, model: model, speakers: speakers)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            running = false
            status = ""
            expectedFinish = nil
        }
    }

    private func transcribe(_ file: URL, language: String, model: String, speakers: Bool) async throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw TranscriptionError.fileNotFound(file.path)
        }
        let audioSeconds = (try? await AVURLAsset(url: file).load(.duration).seconds) ?? 0
        let started = Date()
        expectedFinish = started.addingTimeInterval(audioSeconds * Throughput.ratio(model: model, speakers: speakers))

        let turns = speakers ? try await speakerTurns(file) : []
        let options = decodingOptions(language: language, wordTimestamps: !turns.isEmpty)
        let preparing = Date()
        try await prepare(model: model, file: file, options: options)
        let prepareTime = Date().timeIntervalSince(preparing)  // loading, download, benchmark: not part of the estimate
        expectedFinish = expectedFinish?.addingTimeInterval(prepareTime)
        let results = try await whisper(file, options)
        try Task.checkCancellation()
        if audioSeconds > 60 {  // short clips are dominated by fixed overhead and would skew the estimate
            let work = Date().timeIntervalSince(started) - prepareTime
            Throughput.record(work / audioSeconds, model: model, speakers: speakers)
        }

        let segments = results.flatMap(\.segments)
        timings = results.map(\.timings)
        segmentStats = segments.map {
            SegmentStats(temperature: $0.temperature, avgLogprob: $0.avgLogprob, compressionRatio: $0.compressionRatio)
        }
        (text, srt) = formatTranscript(segments, turns: turns)
        progress = 1
    }

    // MARK: Speakers

    /// FluidAudio: pyannote segmentation + WeSpeaker embeddings on CoreML. Speakers numbered by first appearance.
    private func speakerTurns(_ file: URL) async throws -> [SpeakerTurn] {
        let diarizer = try await loadDiarizer()
        status = localized("Recognizing speakers…", "Sprekers herkennen…")
        let segments = try await Task.detached {
            try diarizer.performCompleteDiarization(try AudioConverter().resampleAudioFile(file)).segments
        }.value
        try Task.checkCancellation()
        var numbers: [String: Int] = [:]
        return segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }.map { segment in
            let number = numbers[segment.speakerId] ?? numbers.count
            numbers[segment.speakerId] = number
            return SpeakerTurn(start: segment.startTimeSeconds, end: segment.endTimeSeconds, speaker: number)
        }
    }

    private func loadDiarizer() async throws -> DiarizerManager {
        if let diarizer { return diarizer }
        status = localized("Loading speaker model…", "Sprekersmodel laden…")
        var config = DiarizerConfig()
        config.clusteringThreshold = Tuning.diarizerThreshold
        let manager = DiarizerManager(config: config)
        manager.initialize(models: try await DiarizerModels.downloadIfNeeded())
        diarizer = manager
        return manager
    }

    // MARK: Whisper

    private func decodingOptions(language: String, wordTimestamps: Bool) -> DecodingOptions {
        DecodingOptions(
            language: language == "auto" ? nil : language,
            temperatureFallbackCount: Tuning.temperatureFallbacks,
            detectLanguage: language == "auto",
            skipSpecialTokens: true,
            wordTimestamps: wordTimestamps,
            compressionRatioThreshold: Tuning.threshold("WHISPER_COMPRESSION", default: 2.4),
            logProbThreshold: Tuning.threshold("WHISPER_LOGPROB", default: -1.0),
            // WhisperKit's default -1.5 re-decoded 84 of 73 Dutch windows at higher temperature. Off: no fallbacks,
            // 31% faster, 13% more words, no suspect segments (2026-10-14, M5, 25-min meeting).
            firstTokenLogProbThreshold: Tuning.threshold("WHISPER_FIRSTTOKEN", default: nil),
            concurrentWorkerCount: Tuning.workers,
            chunkingStrategy: Tuning.chunking
        )
    }

    /// Loads the model on the compute path: environment override, else the remembered benchmark winner, else benchmark now.
    private func prepare(model: String, file: URL, options: DecodingOptions) async throws {
        let wanted =
            Tuning.compute ?? UserDefaults.standard.string(forKey: StoredSetting.compute).flatMap(ComputePath.init)
        if !pipelines.isEmpty, loadedModel == model, let wanted, loadedPath == wanted { return }

        pipelines = []
        let folder = try await modelFolder(model)
        status = localized("Loading model…", "Model laden…")
        progress = nil
        let path: ComputePath
        if let wanted {
            pipelines = try await load(folder, wanted.pipelines)
            path = wanted
        } else {
            (path, pipelines) = try await benchmark(folder, file, options)
        }
        loadedModel = model
        loadedPath = path
        computeName = path.label
    }

    /// Model folder in WhisperKit's cache. A cached model skips the Hugging Face check (4 s) and works offline.
    private func modelFolder(_ model: String) async throws -> URL {
        let cached = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(model)")
        if FileManager.default.fileExists(atPath: cached.appendingPathComponent("TextDecoder.mlmodelc").path) {
            return cached
        }
        status = localized("Downloading model…", "Model downloaden…")
        return try await WhisperKit.download(variant: model) { [weak self] download in
            Task { @MainActor in self?.progress = download.fractionCompleted }
        }
    }

    private func load(_ folder: URL, _ units: [ComputePath.Units]) async throws -> [WhisperKit] {
        var loaded: [WhisperKit] = []
        for unit in units {
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: unit.encoder, textDecoderCompute: unit.decoder),
                verbose: false,
                logLevel: .none,
                prewarm: true
            )
            loaded.append(try await WhisperKit(config))
        }
        return loaded
    }

    private func whisper(_ file: URL, _ options: DecodingOptions) async throws -> [TranscriptionResult] {
        status = localized("Transcribing on \(computeName)…", "Transcriberen via \(computeName)…")
        progress = 0
        let split = Tuning.split ?? (UserDefaults.standard.object(forKey: StoredSetting.split) as? Double) ?? 0.6

        // Live text from the first part. Segment times are relative to WhisperKit's VAD chunks, so they are no
        // good for progress.
        var seen = Set<TranscriptionSegment>()
        pipelines[0].segmentDiscoveryCallback = { [weak self] segments in
            Task { @MainActor in
                guard let self else { return }
                for segment in segments where !seen.contains(segment) {
                    seen.insert(segment)
                    self.text += segment.text.trimmingCharacters(in: .whitespaces) + " "
                }
            }
        }
        defer { pipelines[0].segmentDiscoveryCallback = nil }

        // Progress from WhisperKit's own counter of finished chunks, weighted by each pipeline's share of the audio.
        // A pipeline resets its counter to zero when it finishes, so keep the highest value seen.
        // The countdown starts from the learned estimate and hands over to the measured pace by 50%. Chunks finish
        // in waves, so on short runs the measured pace is too jumpy to use; there the learned estimate is better.
        let weights = pipelines.count == 2 ? [split, 1 - split] : [1]
        let estimatedFinish = expectedFinish
        let shortRun = (estimatedFinish?.timeIntervalSinceNow ?? .infinity) < 30
        let tracker = Task { [pipelines] in
            var highest = [Double](repeating: 0, count: pipelines.count)
            var first: (time: Date, fraction: Double)?  // pace is measured from here, without the start-up time
            while !Task.isCancelled {
                for index in pipelines.indices {
                    highest[index] = max(highest[index], pipelines[index].progress.fractionCompleted)
                }
                let fraction = min(1, zip(highest, weights).reduce(0) { $0 + $1.0 * $1.1 })
                if fraction > 0 {
                    progress = fraction
                    if first == nil { first = (Date(), fraction) }
                }
                if !shortRun, let first, fraction > first.fraction {
                    let pace = Date().timeIntervalSince(first.time) / (fraction - first.fraction)  // seconds per 100%
                    let measured = Date().addingTimeInterval(pace * (1 - fraction))
                    let trust = min(1, fraction * 2)
                    expectedFinish =
                        estimatedFinish.map {
                            $0.addingTimeInterval(measured.timeIntervalSince($0) * trust)
                        } ?? measured
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { tracker.cancel() }

        if pipelines.count == 2 {
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
            return try await transcribeSplit(pipelines[0], pipelines[1], samples, split: split, options)
        }
        return try await pipelines[0].transcribe(
            audioPath: file.path, decodeOptions: options, callback: continueUnlessCancelled)
    }

    /// Cuts `samples` at a quiet point near `split`, transcribes both parts concurrently, returns results in file time.
    private func transcribeSplit(
        _ first: WhisperKit, _ second: WhisperKit, _ samples: [Float], split: Double, _ options: DecodingOptions
    ) async throws -> [TranscriptionResult] {
        var options = options
        // Two pipelines share the thread budget.
        options.concurrentWorkerCount = max(1, options.concurrentWorkerCount / 2)
        let shared = options
        let cut = quietCut(samples, near: Int(Double(samples.count) * split))
        let offset = Float(cut) / Float(sampleRate)
        async let head: [TranscriptionResult] = first.transcribe(
            audioArray: Array(samples[..<cut]), decodeOptions: shared, callback: continueUnlessCancelled)
        async let tail: [TranscriptionResult] = second.transcribe(
            audioArray: Array(samples[cut...]), decodeOptions: shared, callback: continueUnlessCancelled)
        let (headResults, tailResults) = try await (head, tail)
        for result in tailResults {
            result.segments = result.segments.map { segment in
                var segment = segment
                segment.start += offset
                segment.end += offset
                segment.words = segment.words?.map { word in
                    var word = word
                    word.start += offset
                    word.end += offset
                    return word
                }
                return segment
            }
        }
        return headResults + tailResults
    }

    /// One-time per Mac: times the first two minutes of this file on every compute path and remembers the winner.
    /// The Neural Engine runs parallel decoders one after another, the GPU concurrently, and GPU size scales with
    /// Pro and Max chips, so the winner differs per Mac.
    private func benchmark(_ folder: URL, _ file: URL, _ options: DecodingOptions) async throws -> (
        ComputePath, [WhisperKit]
    ) {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path, startTime: 0, endTime: 120)
        var seconds: [ComputePath: Double] = [:]
        var loaded: [ComputePath: WhisperKit] = [:]

        func time(_ path: ComputePath, _ work: () async throws -> Void) async throws {
            status = localized(
                "Finding fastest path (once): \(path.label)…", "Snelste rekenpad bepalen (eenmalig): \(path.label)…")
            let start = Date()
            try await work()
            seconds[path] = Date().timeIntervalSince(start)
            NSLog("benchmark %@: %.1f s", path.rawValue, seconds[path] ?? 0)
            try Task.checkCancellation()
        }

        for path in [ComputePath.gpu, .ane, .mix] {
            let pipeline = try await load(folder, path.pipelines)[0]
            loaded[path] = pipeline
            try await time(path) {
                _ = try await pipeline.transcribe(audioArray: samples, decodeOptions: options) as [TranscriptionResult]
            }
        }
        loaded[.gpu] = nil  // free memory, never part of dual
        guard let mix = loaded[.mix], let ane = loaded[.ane], let mixTime = seconds[.mix], let aneTime = seconds[.ane]
        else {
            preconditionFailure("mix and ane were just benchmarked")
        }
        // GPU-decoder share from measured throughput: rate_mix / (rate_mix + rate_ane)
        let split = (1 / mixTime) / (1 / mixTime + 1 / aneTime)
        try await time(.dual) { _ = try await transcribeSplit(mix, ane, samples, split: split, options) }

        let best = seconds.min { $0.value < $1.value }?.key ?? .ane
        UserDefaults.standard.set(best.rawValue, forKey: StoredSetting.compute)
        UserDefaults.standard.set(split, forKey: StoredSetting.split)
        switch best {
        case .dual: return (best, [mix, ane])
        case .mix: return (best, [mix])
        case .ane: return (best, [ane])
        case .gpu: return (best, try await load(folder, best.pipelines))
        }
    }
}

/// WhisperKit progress callback: nil continues, false stops decoding.
private func continueUnlessCancelled(_: TranscriptionProgress) -> Bool? {
    Task.isCancelled ? false : nil
}
