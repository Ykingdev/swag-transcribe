import SwiftUI

/// Help page shown on the LCD screen instead of the transcript, toggled with the "?" button in the title strip.
/// A sheet of sticker cards in the brand colors, one short tip each.
struct HelpView: View {
    private struct Topic {
        let symbol: String
        let tint: Color
        let title: String
        let body: String
    }

    private static let topics = [
        Topic(
            symbol: "folder.fill", tint: Brand.purple,
            title: localized("Pick a file", "Kies een bestand"),
            body: localized(
                "Click the File button to choose a recording. You can also simply drop an audio or video file onto the player.",
                "Klik op de knop Bestand om een opname te kiezen. Je kunt een audio- of videobestand ook gewoon op de speler slepen."
            )),
        Topic(
            symbol: "play.fill", tint: Brand.pink,
            title: localized("Press play", "Druk op play"),
            body: localized(
                "The big round button starts the transcription, and pressing it again stops it. The first time takes a little longer, because the app downloads the model then.",
                "Met de grote ronde knop start je het transcriberen, en als je er nog een keer op drukt, stopt het weer. De eerste keer duurt het wat langer, omdat de app dan het model downloadt."
            )),
        Topic(
            symbol: "slider.horizontal.3", tint: Brand.lilac,
            title: localized("Settings", "Instellingen"),
            body: localized(
                "On the right of the screen, click the language, the model or the speakers to change them. Turbo is nice and fast, and Large‑v3 is a bit more precise but slower.",
                "Rechts in het scherm pas je de taal, het model en de sprekers aan door erop te klikken. Turbo is lekker snel, en Large‑v3 is net wat preciezer maar ook trager."
            )),
        Topic(
            symbol: "person.2.fill", tint: Brand.purple,
            title: localized("Who's talking?", "Wie praat er?"),
            body: localized(
                "When you turn on Speakers, the app works out who is talking. Every line then gets a name tag, like Speaker 1 or Speaker 2.",
                "Als je Sprekers aanzet, zoekt de app uit wie er aan het woord is. Elke zin krijgt dan een naamkaartje, zoals Spreker 1 of Spreker 2."
            )),
        Topic(
            symbol: "mic.fill", tint: Brand.pink,
            title: "Live",
            body: localized(
                "Press Live and just start talking, and your words appear on the screen right away. Live transcription does not tell different speakers apart.",
                "Druk op Live en begin gewoon te praten, dan verschijnen je woorden meteen op het scherm. Bij live transcriptie worden de sprekers niet uit elkaar gehouden."
            )),
        Topic(
            symbol: "doc.on.doc.fill", tint: Brand.lilac,
            title: localized("Text & SRT", "Tekst & SRT"),
            body: localized(
                "Text shows the transcript as plain, readable text. SRT (SubRip Text) is a subtitle file with timestamps that you can load into your video. Copy and Save let you take it with you.",
                "Bij Tekst lees je het transcript als gewone tekst. SRT (SubRip Text) is een ondertitelbestand met tijden dat je in je video kunt laden. Met Kopieer en Bewaar neem je het mee."
            )),
        Topic(
            symbol: "lock.fill", tint: Brand.purple,
            title: localized("Just yours", "Alleen van jou"),
            body: localized(
                "Everything happens on this Mac, so your recordings and text never go anywhere. Only the models are downloaded from the internet, just once.",
                "Alles gebeurt op deze Mac, dus je opnames en teksten gaan nergens naartoe. Alleen de modellen worden één keer van internet gehaald."
            )),
        Topic(
            symbol: "hand.draw.fill", tint: Brand.pink,
            title: localized("Move me", "Verplaats me"),
            body: localized(
                "You can move the window by grabbing the chrome bar at the top or the purple frame. Press ? again to go back to your transcript.",
                "Je verplaatst het venster door de chromen balk bovenaan of het paarse frame vast te pakken. Druk nog een keer op ? om terug te gaan naar je transcript."
            )),
    ]

    /// False only for `--render help`: ImageRenderer draws scroll views empty.
    var scrolls = true

    var body: some View {
        if scrolls {
            ScrollView { page }
        } else {
            page
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(0..<(Self.topics.count / 2), id: \.self) { row in
                    GridRow {
                        card(Self.topics[row * 2])
                        card(Self.topics[row * 2 + 1])
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            ChunkyText(text: localized("help!", "hulp!"), size: 34)
            OutlinedSparkle(color: Brand.pink).frame(width: 18, height: 18).offset(y: -14)
            OutlinedSparkle(color: Brand.lime).frame(width: 12, height: 12).offset(x: -4, y: 6)
            Text(localized("everything in 8 little steps", "alles in 8 kleine stapjes"))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.lilac)
                .padding(.leading, 8)
            Spacer(minLength: 0)
        }
    }

    private func card(_ topic: Topic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Badge(symbol: topic.symbol, tint: topic.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(topic.body)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [topic.tint.opacity(0.42), topic.tint.opacity(0.14)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(topic.tint.opacity(0.9), lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            Sparkle().fill(.white.opacity(0.7)).frame(width: 10, height: 10).padding(9)
        }
    }

    /// Glossy round icon, like a sticker.
    private struct Badge: View {
        let symbol: String
        let tint: Color

        var body: some View {
            ZStack {
                Circle().fill(tint)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.7), .white.opacity(0)], startPoint: .top, endPoint: .center)
                    )
                    .padding(4)
                Circle().strokeBorder(Brand.ink, lineWidth: 2.5)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: Brand.ink.opacity(0.6), radius: 0, y: 1.5)
            }
            .frame(width: 42, height: 42)
        }
    }
}
