import Testing
import WhisperKit

@testable import SwagTranscribe

@Test func srtTimestampFormatsHoursMinutesSecondsMillis() {
    #expect(srtTimestamp(3661.5) == "01:01:01,500")
    #expect(srtTimestamp(0) == "00:00:00,000")
}

@Test func quietCutLandsInTheSilence() {
    var samples = [Float](repeating: 1, count: 40 * sampleRate)
    for index in 25 * sampleRate..<26 * sampleRate { samples[index] = 0 }
    let cut = quietCut(samples, near: 20 * sampleRate)
    #expect((25 * sampleRate...26 * sampleRate).contains(cut))
}

@Test func quietCutClampsShortAudio() {
    #expect(quietCut([Float](repeating: 1, count: 100), near: 50) == 50)
}

@Test func speakerPicksLargestOverlap() {
    let turns = [SpeakerTurn(start: 0, end: 1.5, speaker: 0), SpeakerTurn(start: 1.5, end: 5, speaker: 1)]
    #expect(speaker(from: 1, to: 3, in: turns) == 1)
    #expect(speaker(from: 6, to: 7, in: turns) == 1)  // in a gap: nearest turn
    #expect(speaker(from: 1, to: 2, in: []) == nil)
}

@Test func transcriptSplitsAtSpeakerChangeInsideASegment() {
    let words = [
        WordTiming(word: " Hallo", tokens: [], start: 0, end: 0.5, probability: 1),
        WordTiming(word: " daar.", tokens: [], start: 0.5, end: 1, probability: 1),
        WordTiming(word: " Ja.", tokens: [], start: 2, end: 2.5, probability: 1),
    ]
    let segment = TranscriptionSegment(start: 0, end: 2.5, text: " Hallo daar. Ja.", words: words)
    let turns = [SpeakerTurn(start: 0, end: 1.2, speaker: 0), SpeakerTurn(start: 1.8, end: 3, speaker: 1)]

    let (text, srt) = formatTranscript([segment], turns: turns, speakerName: "Spreker")

    #expect(text == "Spreker 1: Hallo daar.\n\nSpreker 2: Ja.")
    #expect(
        srt
            == "1\n00:00:00,000 --> 00:00:01,000\nSpreker 1: Hallo daar.\n\n2\n00:00:02,000 --> 00:00:02,500\nSpreker 2: Ja.\n"
    )
}

@Test func transcriptWithoutSpeakersKeepsOneLinePerSegment() {
    let segments = [
        TranscriptionSegment(start: 3, end: 4, text: " Tweede."),
        TranscriptionSegment(start: 0, end: 2, text: " Eerste."),
    ]
    #expect(formatTranscript(segments, turns: []).text == "Eerste.\nTweede.")
}

@Test func durationsReadAsMinutesOrHours() {
    #expect(formatDuration(0) == "0:00")
    #expect(formatDuration(49.6) == "0:50")
    #expect(formatDuration(1505) == "25:05")
    #expect(formatDuration(3723) == "1:02:03")
}

@Test func waitingIdeasGrowWithTheWait() {
    #expect(waitingIdeas(for: 30) != waitingIdeas(for: 120))
    #expect(waitingIdeas(for: 120) != waitingIdeas(for: 600))
    #expect(!waitingIdeas(for: 600).isEmpty)
}

@Test func speakerLabelIsFoundOnlyAtLineStart() {
    let label = speakerLabel(in: "Spreker 12: Hallo", name: "Spreker")
    #expect(label?.number == 12)
    #expect(label?.length == "Spreker 12: ".count)
    #expect(speakerLabel(in: "Hallo Spreker 1: daar", name: "Spreker") == nil)
    #expect(speakerLabel(in: "Spreker: geen nummer", name: "Spreker") == nil)
}

@Test func chatMessagesNeedALabelOnEveryParagraph() {
    let messages = chatMessages(in: "Spreker 1: Hoi.\n\nSpreker 2: Hallo!", name: "Spreker")
    #expect(messages?.map(\.speaker) == [1, 2])
    #expect(messages?.map(\.text) == ["Hoi.", "Hallo!"])
    #expect(chatMessages(in: "Gewone zin.\nNog een.", name: "Spreker") == nil)
    #expect(chatMessages(in: "", name: "Spreker") == nil)
    #expect(chatMessages(in: "Spreker 1: Ja, ik\n\nheb het.", name: "Spreker")?.map(\.text) == ["Ja, ik heb het."])
}
