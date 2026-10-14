import SwiftUI

/// A transcript with speakers as a group chat: one bubble per speaker turn in that speaker's color.
/// Odd speakers sit on the left, even speakers on the right, like two sides of a conversation.
struct ChatTranscript: View {
    let messages: [(speaker: Int, text: String)]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(messages.indices, id: \.self) { index in
                    ChatBubble(speaker: messages[index].speaker, text: messages[index].text)
                }
            }
            .padding(14)
        }
    }
}

struct ChatBubble: View {
    let speaker: Int
    let text: String

    private var onLeft: Bool { speaker % 2 == 1 }

    var body: some View {
        let color = SpeakerColors.color(for: speaker)
        // The pointed corner faces the speaker's side, like a speech bubble tail.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: onLeft ? 4 : 16, bottomLeadingRadius: 16, bottomTrailingRadius: 16,
            topTrailingRadius: onLeft ? 16 : 4, style: .continuous)
        HStack(spacing: 0) {
            if !onLeft { Spacer(minLength: 70) }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(localized("Speaker", "Spreker")) \(speaker)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                Text(text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(shape.fill(color.opacity(0.18)))
            .overlay(shape.strokeBorder(color.opacity(0.85), lineWidth: 1.5))
            if onLeft { Spacer(minLength: 70) }
        }
    }
}
