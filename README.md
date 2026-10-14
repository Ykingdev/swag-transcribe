# swag-transcribe

A native macOS app that turns audio and video into text, on your own Mac. It runs OpenAI's Whisper through
[WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML), can tell speakers apart with
[FluidAudio](https://github.com/FluidInference/FluidAudio), and wears a Y2K media-player skin.

Nothing leaves the Mac. The only network traffic is the one-time model download.

## What it does

- **File transcription** of anything macOS can decode: mp3, m4a, wav, mp4, mov and more.
- **Speaker recognition**: every line gets a label like "Speaker 1", shown as colored chat bubbles.
- **Two outputs**: readable text, and SRT subtitles (SubRip Text) with timestamps for video editors.
- **Live mode**: transcribes the microphone as you talk, with Apple's on-device speech recognition.
- **Time estimate**: shows how long a file will take before you start, and counts down while it works.
- **English and Dutch UI**, following the language of the Mac.

## Requirements

- Apple Silicon Mac with macOS 15 or later.
- Xcode or the Xcode Command Line Tools with Swift 6.
- About 1.6 GB of disk space for the Turbo model, 3 GB more for Large-v3.

## Build and run

```sh
./build.sh
open swag-transcribe.app
```

`build.sh` compiles a release build, renders the app icon from SwiftUI, adds the translations and signs the
bundle ad hoc. The first build downloads and compiles the Swift packages, which takes a few minutes.

Models are downloaded on first use to `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/`. Speaker
models go to FluidAudio's folder in `~/Library/Application Support/`.

## Using it

1. Click **File**, or drop a file onto the player.
2. Optionally click the settings on the right of the screen: language, model, speakers.
3. Press the round **play** button. Press it again to stop.
4. Switch between **Text** and **SRT**, then **Copy** or **Save**.

Drag the chrome title bar or the purple frame to move the window. The **?** button explains everything inside
the app.

The very first transcription on a Mac takes longer. The model is downloaded, macOS prepares it for the chip,
and the app benchmarks which chip parts are fastest on this machine. That benchmark runs once and is
remembered.

## How it works

```
audio file
   │
   ├─▶ FluidAudio diarization (optional)      pyannote segmentation + WeSpeaker embeddings, Core ML
   │        → speaker turns
   │
   ├─▶ WhisperKit, Whisper large-v3 Turbo     audio cut at a quiet point into two parts:
   │        part 1: encoder on Neural Engine, decoder on GPU
   │        part 2: encoder and decoder on Neural Engine
   │        both parts run at the same time
   │
   └─▶ formatting                              words matched to speaker turns,
            → text paragraphs, chat bubbles, SRT cues
```

### Source layout

| File | What it holds |
|---|---|
| `SwagTranscribeApp.swift` | App entry, plus the headless `--cli` and `--render` modes |
| `Transcriber.swift` | Diarization, model loading, the compute-path benchmark, progress and countdown |
| `Formatting.swift` | Pure functions: SRT timestamps, quiet-point search, speaker matching, transcript layout |
| `Settings.swift` | Models, compute paths, UI language, stored settings, environment overrides |
| `WaitTime.swift` | Learned speed per Mac, duration formatting, things to do while waiting |
| `LiveTranscriber.swift` | Microphone transcription with Apple's Speech framework |
| `ContentView.swift` | The player layout and its actions |
| `ChatTranscript.swift` | Speaker turns as chat bubbles |
| `HelpView.swift` | The in-app help page |
| `Skin.swift` | Chassis shape, glossy buttons, LCD text, progress bar, marquee, speaker colors, window setup |
| `Logo.swift` | The logo and the app icon, drawn in SwiftUI |

## Why it is built this way

All numbers below were measured on a base M5 MacBook with 16 GB of RAM, on a 25-minute Dutch meeting recording.

### Native instead of Python

The first version called `mlx_whisper` in a Python virtual environment. Moving to WhisperKit and FluidAudio
makes the app one self-contained bundle that runs on any Apple Silicon Mac without a Python setup, and lets it
use the Neural Engine.

### Memory is not the bottleneck

The app peaks at 0.75 to 2.6 GB depending on the compute path. Most of the time goes into the decoder, which
writes text one token at a time. Each token takes about 8.7 ms, almost all of it call overhead rather than
math. A smaller quantized model (632 MB instead of 1.5 GB) was not faster, because the Neural Engine expands
the weights back to 16-bit anyway.

### Whisper's first-token threshold is off

WhisperKit re-decodes a 30-second window at a higher temperature when the first token's probability is below
a fixed threshold. On Dutch meeting audio that fired for 84 of 73 windows, so almost everything was decoded
twice. Turning that one threshold off made transcription 31% faster and produced 13% more words, with zero
segments flagged as repetitive or low-confidence. The other two safety thresholds, for repetition and average
probability, stay on. With the first one off they never fired on this audio. Turning the probability threshold
off as well let garbled and repeated lines into the text.

### Two pipelines on two chip parts

The Neural Engine runs parallel decoders one after another, while the GPU runs them at the same time. The best
setup on the M5 is to use both: the audio is cut at the quietest moment near a computed split point, one half
decodes on the GPU and the other on the Neural Engine, and the timestamps of the second half are shifted back
into file time.

| Compute path | Time for 25 min of audio |
|---|---|
| Everything on the GPU | 163 s |
| Everything on the Neural Engine | 81 s |
| Encoder on Neural Engine, decoder on GPU | 61 to 65 s |
| Two pipelines at the same time | 50 s |

The fastest path differs per Mac. A Pro or Max chip has a bigger GPU but the same Neural Engine as the base
chip. So on first use the app times all four paths on the first two minutes of your file and remembers the
winner. The split ratio comes from the measured speed of the two pipelines.

### Fewer tasks than CPU cores

WhisperKit's sampler blocks one Swift concurrency thread per task, and Swift has one such thread per CPU core.
Two pipelines with 16 tasks each starved the pool on the 10-core M5 and deadlocked. The app now uses the core
count minus two, split over the pipelines. 8, 16 and 32 tasks measured equally fast, so nothing is lost.

### Speakers at word level

Speaker turns from diarization are matched to Whisper's word timestamps, so a speaker change in the middle of a
Whisper segment is placed correctly. A word that falls in a silence between two turns gets the nearest speaker.
Speaker clustering uses a threshold of 0.6, which found exactly four speakers on a four-speaker test recording,
where 0.7 merged them into two.

### A countdown that learns

After every file longer than a minute, the app stores how many seconds of work one second of audio took, per
model and with or without speakers. Model loading and the benchmark are left out. During a run, progress comes
from WhisperKit's count of finished chunks, because WhisperKit reports segment times relative to each chunk
rather than to the file. The countdown starts from the learned estimate and hands over to the measured pace by
50% progress. On runs under half a minute it keeps the learned estimate, because chunks finish in waves and the
measured pace jumps around. In tests it stayed within a few percent of the real finish time.

### Two languages in code

The UI has exactly two languages, so strings are picked with a small `localized(english, dutch)` function
instead of a String Catalog. A catalog would need a resource bundle next to the executable, which complicates
the hand-built app bundle and its signature. The system dialogs and permission prompts are still translated
through `en.lproj` and `nl.lproj` in the bundle.

## Development

```sh
swift build                                  # debug build
swift test                                   # unit tests for the pure functions
swift format lint -r Sources Tests Package.swift
```

The code style is in `.swift-format`: four-space indentation and 120 characters per line.

### Headless modes

```sh
APP=swag-transcribe.app/Contents/MacOS/SwagTranscribe
$APP --cli recording.m4a --speakers          # prints status, text, SRT, decode stats and timings
$APP --render ui screenshot.png              # icon | logo | ui | help
```

`--render` uses SwiftUI's `ImageRenderer`, which draws scroll views empty, so the transcript area stays blank
in `ui` renders.

### Environment overrides for benchmarking

| Variable | Effect |
|---|---|
| `WHISPER_COMPUTE` | Force a compute path: `gpu`, `ane`, `mix` or `dual` |
| `WHISPER_MODEL` | Any variant name from `argmaxinc/whisperkit-coreml` |
| `WHISPER_LANG` | Spoken language for `--cli`, for example `nl` |
| `WHISPER_SPLIT` | GPU share of the audio in `dual`, for example `0.55` |
| `WHISPER_WORKERS` | Concurrent tasks per run |
| `WHISPER_FALLBACKS` | Number of temperature fallbacks |
| `WHISPER_FIRSTTOKEN`, `WHISPER_LOGPROB`, `WHISPER_COMPRESSION` | Decoding thresholds, a number or `none` |
| `WHISPER_CHUNKING` | `none` to disable voice-activity chunking |
| `DIARIZER_THRESHOLD` | Speaker clustering threshold; lower finds more speakers |

### Stored settings

```sh
defaults read dev.webads.swag-transcribe                  # benchmark winner, split and learned speeds
defaults delete dev.webads.swag-transcribe compute        # benchmark again on the next file
```

## Ideas for later

- **Decoder export for the Neural Engine.** Keeping the decoder's key-value cache on the chip and decoding
  several windows per call would attack the 8.7 ms per-token overhead directly. This is an estimated 3 to 5
  times faster decoder, but it needs a WhisperKit fork and a new Core ML export.
- **Fine-tuning on Dutch.** A model that is more confident on Dutch meeting audio would need fewer fallbacks
  and make fewer mistakes.
- **Live speaker labels.** These would need streaming diarization.
