import AppKit
import SwiftUI

/// Y2K media-player skin: a glossy purple chassis, a chrome title strip, a black LCD screen with lime text,
/// and bulging glossy buttons. All drawn in SwiftUI, so it also renders in `--render ui`.
enum Skin {
    /// The window is a fixed-size canvas; all regions below are in these coordinates.
    static let size = CGSize(width: 1000, height: 700)

    static let chassisTop = Color(red: 0.82, green: 0.69, blue: 1.00)
    static let chassisBottom = Color(red: 0.40, green: 0.16, blue: 0.84)
    static let rim = Color(red: 0.18, green: 0.05, blue: 0.36)
    static let screen = Color(red: 0.03, green: 0.02, blue: 0.06)
    static let bezel = Color(white: 0.32)
    static let lcd = Brand.lime
    static let lcdDim = Brand.lime.opacity(0.45)

    static func lcdFont(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
}

extension View {
    /// Dragging this view moves the window, also when the app is inactive. AppKit's `isMovableByWindowBackground`
    /// does not see SwiftUI drawings as background, so the skin opts in per view.
    func dragsWindow() -> some View {
        gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
    }

    /// Places a view on the `Skin.size` canvas.
    func placed(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }
}

/// The outline of the player: main body, a left wing for the side buttons, and a pod for the transport controls.
struct Chassis: Shape {
    static let parts: [(rect: CGRect, radius: CGFloat)] = [
        (CGRect(x: 170, y: 18, width: 812, height: 566), 48),  // body
        (CGRect(x: 16, y: 96, width: 232, height: 438), 72),  // left wing
        (CGRect(x: 252, y: 498, width: 516, height: 188), 84),  // control pod
    ]

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / Skin.size.width
        let scaleY = rect.height / Skin.size.height
        var path = Path()
        for part in Self.parts {
            let scaled = CGRect(
                x: rect.minX + part.rect.minX * scaleX, y: rect.minY + part.rect.minY * scaleY,
                width: part.rect.width * scaleX, height: part.rect.height * scaleY)
            path.addRoundedRect(
                in: scaled, cornerSize: CGSize(width: part.radius * scaleX, height: part.radius * scaleY),
                style: .continuous)
        }
        return path
    }
}

struct ChassisView: View {
    var body: some View {
        ZStack {
            // Stroke first, fill second: the fill hides the seams where the parts overlap, only the outer rim stays.
            Chassis().stroke(Skin.rim, lineWidth: 10)
            Chassis().fill(
                LinearGradient(colors: [Skin.chassisTop, Skin.chassisBottom], startPoint: .top, endPoint: .bottom))
            Chassis().fill(
                LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0)], startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.3)))
            Chassis().fill(ScanLines().opacity(0.06))
        }
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .overlay {
            ForEach(Self.screws, id: \.x) { point in Screw().frame(width: 16, height: 16).position(point) }
        }
    }

    private static let screws = [
        CGPoint(x: 206, y: 50), CGPoint(x: 950, y: 552), CGPoint(x: 206, y: 552), CGPoint(x: 62, y: 116),
        CGPoint(x: 296, y: 650), CGPoint(x: 724, y: 650),
    ]
}

/// Chrome screw head with a slot.
struct Screw: View {
    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Circle().strokeBorder(Skin.rim, lineWidth: 1.5)
            Capsule().fill(Skin.rim.opacity(0.8)).frame(height: 2.5).padding(.horizontal, 3).rotationEffect(
                .degrees(-35))
        }
    }
}

/// Fine horizontal stripes, as on brushed plastic skins.
struct ScanLines: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        ImagePaint(image: Image(nsImage: Self.tile), scale: 1)
    }

    private static let tile: NSImage = {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 2).fill()
        image.unlockFocus()
        return image
    }()
}

/// Bulging plastic button: tinted body, white gloss on the top half, darker bottom, dark rim.
struct GlossyButtonStyle: ButtonStyle {
    enum Form { case pill, rounded, circle }

    var form = Form.rounded
    var tint = Brand.lilac
    /// Lit buttons show lime text, like an active mode on a hardware player.
    var lit = false

    func makeBody(configuration: Configuration) -> some View {
        GlossyButton(configuration: configuration, form: form, tint: tint, lit: lit)
    }

    private struct GlossyButton: View {
        let configuration: Configuration
        let form: Form
        let tint: Color
        let lit: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = shape
            configuration.label
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(lit ? Brand.lime : .white)
                .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: 1.5)
                .padding(.horizontal, form == .circle ? 0 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack {
                        shape.fill(tint)
                        shape.fill(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom))
                        shape.fill(
                            LinearGradient(
                                colors: [.white.opacity(0.75), .white.opacity(0.05)], startPoint: .top,
                                endPoint: .center)
                        )
                        .padding(form == .circle ? 7 : 4)
                        .mask(alignment: .top) { Rectangle().frame(height: 1000).offset(y: -500) }
                        shape.stroke(Skin.rim, lineWidth: 2.5)
                        if lit { shape.stroke(Brand.lime.opacity(0.8), lineWidth: 1.5).padding(3) }
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .brightness(configuration.isPressed ? -0.1 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(shape)
        }

        private var shape: AnyShape {
            switch form {
            case .pill: AnyShape(Capsule())
            case .rounded: AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            case .circle: AnyShape(Circle())
            }
        }
    }
}

/// Glowing monospaced LCD text.
struct LCDText: View {
    let text: String
    var size: CGFloat = 13
    var color = Skin.lcd

    init(_ text: String, size: CGFloat = 13, color: Color = Skin.lcd) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Skin.lcdFont(size))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.6), radius: 4)
    }
}

/// One bright color per speaker, all readable on the black LCD.
enum SpeakerColors {
    static let palette: [Color] = [
        Brand.lime,
        Brand.pink,
        Color(red: 0.31, green: 0.89, blue: 1.00),  // cyan
        Color(red: 1.00, green: 0.67, blue: 0.20),  // orange
        Brand.lilac,
        Color(red: 1.00, green: 0.88, blue: 0.30),  // yellow
    ]

    static func color(for speaker: Int) -> Color { palette[(speaker - 1) % palette.count] }

    /// `text` in `base`, with every "Speaker N:" label bold in that speaker's color.
    static func highlight(_ text: String, base: Color) -> AttributedString {
        let name = localized("Speaker", "Spreker")
        var result = AttributedString()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if !result.characters.isEmpty { result += AttributedString("\n") }
            var rest = line
            if let label = speakerLabel(in: line, name: name) {
                var tag = AttributedString(line.prefix(label.length))
                tag.foregroundColor = color(for: label.number)
                tag.font = .system(size: 13, weight: .black, design: .monospaced)
                result += tag
                rest = line.dropFirst(label.length)
            }
            var body = AttributedString(rest)
            body.foregroundColor = base
            result += body
        }
        return result
    }
}

/// Scrolling LCD ticker. Each full pass shows the next message.
struct Marquee: View {
    let messages: [String]
    var size: CGFloat = 12
    var color = Brand.pink
    /// Points per second.
    var speed: Double = 55

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let time = context.date.timeIntervalSinceReferenceDate
                let longest = Double(messages.map(\.count).max() ?? 0) * size * 0.6  // monospaced glyph width
                let lap = (geometry.size.width + longest) / speed
                let message = messages.isEmpty ? "" : messages[Int(time / lap) % messages.count]
                LCDText(message, size: size, color: color)
                    .fixedSize()
                    .offset(x: geometry.size.width - time.truncatingRemainder(dividingBy: lap) * speed)
            }
        }
        .frame(height: size * 1.4)
        .clipped()
    }
}

/// Segmented LCD bar. With no value while active, a block of segments sweeps back and forth.
struct LCDProgress: View {
    let value: Double?
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !(active && value == nil))) { context in
            GeometryReader { geometry in
                let count = max(1, Int(geometry.size.width / 8))
                let lit = litRange(count: count, time: context.date.timeIntervalSinceReferenceDate)
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { index in
                        Rectangle().fill(lit.contains(index) ? Skin.lcd : Skin.lcd.opacity(0.12))
                    }
                }
                .shadow(color: Skin.lcd.opacity(0.5), radius: 3)
            }
        }
        .frame(height: 10)
    }

    private func litRange(count: Int, time: TimeInterval) -> Range<Int> {
        if let value { return 0..<Int((Double(count) * value).rounded()) }
        guard active else { return 0..<0 }
        let width = max(3, count / 8)
        let phase = abs((time * 0.6).truncatingRemainder(dividingBy: 2) - 1)  // 1 -> 0 -> 1, triangle wave
        let start = Int(Double(count - width) * (1 - phase))
        return start..<(start + width)
    }
}

/// Makes the hosting window borderless-looking: transparent and without system buttons.
/// The skin draws its own shadow, title strip and window buttons.
struct SkinnedWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
    }
}
