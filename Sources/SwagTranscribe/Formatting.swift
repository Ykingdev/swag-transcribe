import Foundation
import WhisperKit

/// Sample rate WhisperKit and FluidAudio work in.
let sampleRate = 16_000

/// A stretch of audio attributed to one speaker by diarization.
struct SpeakerTurn: Equatable {
    let start: Float
    let end: Float
    let speaker: Int
}

/// Seconds as an SRT timestamp, "HH:MM:SS,mmm".
func srtTimestamp(_ seconds: Float) -> String {
    let ms = Int((seconds * 1000).rounded())
    return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
}

/// Sample index of the quietest 0.5 s within ±10 s of `target`, so a split never cuts through a word.
func quietCut(_ samples: [Float], near target: Int) -> Int {
    let window = sampleRate / 2
    let low = max(0, target - 10 * sampleRate)
    let high = min(samples.count - window, target + 10 * sampleRate)
    guard low < high else { return min(max(target, 0), samples.count) }
    var best = target
    var bestEnergy = Float.infinity
    for start in stride(from: low, to: high, by: sampleRate / 10) {
        var energy: Float = 0
        for index in start..<(start + window) { energy += samples[index] * samples[index] }
        if energy < bestEnergy {
            bestEnergy = energy
            best = start + window / 2
        }
    }
    return best
}

/// Speaker with the most overlap with `start...end`. A word in a gap between turns gets the nearest speaker:
/// without overlap the value is minus the gap, so the maximum is the closest turn. Nil only without turns.
func speaker(from start: Float, to end: Float, in turns: [SpeakerTurn]) -> Int? {
    var best: Int?
    var bestOverlap = -Float.infinity
    for turn in turns {
        let overlap = min(end, turn.end) - max(start, turn.start)
        if overlap > bestOverlap {
            best = turn.speaker
            bestOverlap = overlap
        }
    }
    return best
}

/// Readable text plus SRT cues. With speaker turns, cues split at every speaker change (word level)
/// and the text gets one paragraph per speaker turn.
func formatTranscript(
    _ segments: [TranscriptionSegment], turns: [SpeakerTurn], speakerName: String = localized("Speaker", "Spreker")
) -> (text: String, srt: String) {
    typealias Group = (start: Float, end: Float, speaker: Int?, text: String)
    var groups: [Group] = []
    for segment in segments.sorted(by: { $0.start < $1.start }) {
        let units: [(start: Float, end: Float, text: String)] =
            segment.words.map { $0.map { ($0.start, $0.end, $0.word) } } ?? [(segment.start, segment.end, segment.text)]
        for (index, unit) in units.enumerated() {
            let who = turns.isEmpty ? nil : speaker(from: unit.start, to: unit.end, in: turns)
            if index > 0, let last = groups.last, last.speaker == who {
                groups[groups.count - 1].end = unit.end
                groups[groups.count - 1].text += unit.text
            } else {
                groups.append((unit.start, unit.end, who, unit.text))
            }
        }
    }
    groups.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }

    var lines: [String] = []
    var cues: [String] = []
    for (index, group) in groups.enumerated() {
        let text = group.text.trimmingCharacters(in: .whitespaces)
        let label = group.speaker.map { "\(speakerName) \($0 + 1): " } ?? ""
        if turns.isEmpty || index == 0 || group.speaker != groups[index - 1].speaker {
            lines.append(label + text)
        } else {
            lines[lines.count - 1] += " " + text
        }
        cues.append("\(index + 1)\n\(srtTimestamp(group.start)) --> \(srtTimestamp(group.end))\n\(label)\(text)\n")
    }
    return (lines.joined(separator: turns.isEmpty ? "\n" : "\n\n"), cues.joined(separator: "\n"))
}

/// The speaker label at the start of a transcript or SRT line, as written by `formatTranscript`:
/// "Spreker 2: …" gives (number: 2, length: 11). Nil when the line has no label.
func speakerLabel(in line: Substring, name: String) -> (number: Int, length: Int)? {
    guard line.hasPrefix(name + " ") else { return nil }
    let afterName = line.dropFirst(name.count + 1)
    let digits = afterName.prefix { $0.isNumber }
    guard let number = Int(digits), afterName.dropFirst(digits.count).hasPrefix(": ") else { return nil }
    return (number, name.count + 1 + digits.count + 2)
}

/// Speaker paragraphs of a transcript as chat messages. A paragraph without a label continues the previous
/// message. Nil when the transcript does not start with a speaker label.
func chatMessages(in text: String, name: String) -> [(speaker: Int, text: String)]? {
    let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    var messages: [(speaker: Int, text: String)] = []
    for paragraph in paragraphs {
        if let label = speakerLabel(in: Substring(paragraph), name: name) {
            messages.append((label.number, String(paragraph.dropFirst(label.length))))
        } else if !messages.isEmpty {
            messages[messages.count - 1].text += " " + paragraph
        } else {
            return nil
        }
    }
    return messages.isEmpty ? nil : messages
}
