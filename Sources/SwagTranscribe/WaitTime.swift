import Foundation

/// How long a transcription takes on this Mac, learned from earlier runs: seconds of work per second of audio,
/// per model and speaker setting. Model loading and the one-time benchmark are not counted.
enum Throughput {
    /// Before the first run: a cautious guess. A base M5 measured 0.033 for Turbo, 0.046 with speakers.
    static func ratio(model: String, speakers: Bool) -> Double {
        if let stored = UserDefaults.standard.object(forKey: key(model, speakers)) as? Double { return stored }
        let base = model == WhisperModel.turbo.rawValue ? 0.05 : 0.15
        return speakers ? base + 0.015 : base
    }

    /// Averages with the previous value, so one odd run does not throw the estimate off.
    static func record(_ ratio: Double, model: String, speakers: Bool) {
        let key = key(model, speakers)
        let previous = UserDefaults.standard.object(forKey: key) as? Double
        UserDefaults.standard.set(previous.map { ($0 + ratio) / 2 } ?? ratio, forKey: key)
    }

    private static func key(_ model: String, _ speakers: Bool) -> String {
        "ratio.\(model).\(speakers ? "speakers" : "plain")"
    }
}

/// Seconds as "m:ss", or "h:mm:ss" from an hour.
func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = total / 60 % 60
    let rest = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
}

/// Things to do that fit in the expected wait.
func waitingIdeas(for seconds: Double) -> [String] {
    if seconds < 60 {
        return [
            localized("Take a sip of water", "Neem een slok water"),
            localized("Stretch your arms up high", "Rek je armen hoog boven je hoofd"),
            localized("Do ten squats", "Doe tien squats"),
            localized("Look at something far away for 20 seconds", "Kijk 20 seconden naar iets in de verte"),
        ]
    }
    if seconds < 300 {
        return [
            localized("Make a cup of tea", "Zet een kop thee"),
            localized("Tidy up your desk a little", "Ruim je bureau een beetje op"),
            localized("Send someone a sweet message", "Stuur iemand een lief berichtje"),
            localized("Refill your water bottle", "Vul je waterfles bij"),
            localized("Put on your favorite song", "Zet je lievelingsnummer op"),
        ]
    }
    return [
        localized("Take a walk around the block", "Loop een rondje om het blok"),
        localized("Boil a soft egg, that takes 6 minutes", "Kook een zacht eitje, dat duurt 6 minuten"),
        localized("Put on a whole album", "Zet een heel album op"),
        localized("Do the dishes", "Doe de afwas"),
        localized("Call someone you miss", "Bel iemand die je mist"),
    ]
}
