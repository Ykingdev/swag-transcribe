import CoreML
import Foundation
import WhisperKit

/// UI language follows the Mac: Dutch when the first preferred language is Dutch, English otherwise.
/// Two languages, so plain code instead of a String Catalog: no resource bundle to ship and sign next to the app.
enum UILanguage {
    static let isDutch = Locale.preferredLanguages.first?.hasPrefix("nl") ?? false
}

/// The English or Dutch text, for the current UI language.
func localized(_ english: String, _ dutch: String) -> String {
    UILanguage.isDutch ? dutch : english
}

/// WhisperKit CoreML variants on argmaxinc/whisperkit-coreml, downloaded on first use.
enum WhisperModel: String, CaseIterable, Identifiable {
    case turbo = "openai_whisper-large-v3-v20240930_turbo"  // 1.5 GB
    case largeV3 = "openai_whisper-large-v3-v20240930"  // 1.5 GB

    var id: String { rawValue }
    var label: String {
        switch self {
        case .turbo: "Turbo"
        case .largeV3: "Large-v3"
        }
    }
}

/// Where the Whisper encoder and decoder run. The fastest one differs per Mac and is picked by a one-time benchmark.
/// M5 base, 25-min meeting: dual 50 s, mix 65 s, ane 81 s, gpu 163 s.
enum ComputePath: String, CaseIterable {
    case gpu, ane, mix, dual

    typealias Units = (encoder: MLComputeUnits, decoder: MLComputeUnits)

    /// One entry per WhisperKit pipeline to load. `dual` runs two pipelines side by side on two halves of the audio.
    var pipelines: [Units] {
        switch self {
        case .gpu: [(.cpuAndGPU, .cpuAndGPU)]
        case .ane: [(.cpuAndNeuralEngine, .cpuAndNeuralEngine)]
        case .mix: [(.cpuAndNeuralEngine, .cpuAndGPU)]
        case .dual: ComputePath.mix.pipelines + ComputePath.ane.pipelines
        }
    }

    var label: String {
        switch self {
        case .gpu: "GPU"
        case .ane: "Neural Engine"
        case .mix: "Neural Engine + GPU"
        case .dual: localized("GPU and Neural Engine together", "GPU en Neural Engine tegelijk")
        }
    }
}

/// Values remembered between launches.
enum StoredSetting {
    /// Benchmark winner, a `ComputePath` raw value. Reset: `defaults delete dev.webads.swag-transcribe compute`
    static let compute = "compute"
    /// Share of the audio for the GPU-decoder half in `dual`, derived from the benchmark.
    static let split = "split"
}

/// Environment overrides for benchmarking. Unset, the app uses the measured best settings.
enum Tuning {
    private static let env = ProcessInfo.processInfo.environment

    static var compute: ComputePath? { env["WHISPER_COMPUTE"].flatMap(ComputePath.init) }
    static var model: String? { env["WHISPER_MODEL"] }
    static var language: String? { env["WHISPER_LANG"] }
    static var split: Double? { env["WHISPER_SPLIT"].flatMap(Double.init) }
    static var temperatureFallbacks: Int { env["WHISPER_FALLBACKS"].flatMap(Int.init) ?? 5 }
    static var chunking: ChunkingStrategy { env["WHISPER_CHUNKING"] == "none" ? .none : .vad }
    /// Speaker clustering; lower finds more speakers.
    static var diarizerThreshold: Float { env["DIARIZER_THRESHOLD"].flatMap(Float.init) ?? 0.6 }

    /// WhisperKit's sampler blocks one Swift pool thread per task, and the pool has one thread per CPU core.
    /// 16 tasks per pipeline x 2 pipelines starved the pool on a 10-core M5 and deadlocked, so stay below the core count.
    /// 8, 16 and 32 tasks measured equally fast.
    static var workers: Int {
        env["WHISPER_WORKERS"].flatMap(Int.init) ?? max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
    }

    /// A decoding threshold, overridable with a number or "none" to disable it.
    static func threshold(_ key: String, default value: Float?) -> Float? {
        guard let raw = env[key] else { return value }
        return raw == "none" ? nil : Float(raw)
    }
}
