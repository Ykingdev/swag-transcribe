import SwiftUI

/// Y2K brand: chunky skewed letters with ink outline and extrusion, a wireframe globe, an orbit ring and sparkles.
enum Brand {
    static let lilac = Color(red: 0.72, green: 0.61, blue: 1.00)
    static let purple = Color(red: 0.45, green: 0.22, blue: 0.95)
    static let lime = Color(red: 0.83, green: 1.00, blue: 0.25)
    static let pink = Color(red: 1.00, green: 0.36, blue: 0.56)
    static let ink = Color(red: 0.07, green: 0.06, blue: 0.10)
}

/// Wide logo for the window header.
struct LogoView: View {
    var height: CGFloat = 96

    var body: some View {
        let unit = height / 100
        ZStack {
            ring(.back, unit)
            Globe(lineScale: unit).frame(width: 92 * unit, height: 92 * unit).offset(x: -52 * unit, y: -2 * unit)
            ring(.front, unit)
            VStack(spacing: -6 * unit) {
                ChunkyText(text: "swag", size: 64 * unit)
                Banner(text: "TRANSCRIBE", size: 13 * unit)
                    .offset(x: 18 * unit)
            }
            .offset(x: 6 * unit, y: 0)
            OutlinedSparkle(color: Brand.pink, lineScale: unit).frame(width: 30 * unit, height: 30 * unit).offset(
                x: -112 * unit, y: -30 * unit)
            OutlinedSparkle(color: Brand.lime, lineScale: unit).frame(width: 20 * unit, height: 20 * unit).offset(
                x: 112 * unit, y: -34 * unit)
            OutlinedSparkle(color: Brand.lilac, lineScale: unit).frame(width: 14 * unit, height: 14 * unit).offset(
                x: 126 * unit, y: -14 * unit)
        }
        .frame(width: 270 * unit, height: height)
        .drawingGroup()
    }

    private func ring(_ half: OrbitRing.Half, _ unit: CGFloat) -> some View {
        OrbitRing(half: half, lineScale: unit)
            .frame(width: 250 * unit, height: 62 * unit)
            .rotationEffect(.degrees(-9))
            .offset(x: -10 * unit, y: 4 * unit)
    }
}

/// macOS app icon, rendered to 1024 x 1024 by `build.sh`.
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Brand.purple, Brand.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(Brand.ink, lineWidth: 22))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            ring(.back)
            Globe(lineScale: 5.5).frame(width: 470, height: 470).offset(y: -40)
            ring(.front)
            ChunkyText(text: "swag", size: 250).offset(x: -10, y: 70)
            OutlinedSparkle(color: Brand.pink, lineScale: 5.5).frame(width: 150, height: 150).offset(x: -270, y: -260)
            OutlinedSparkle(color: Brand.lime, lineScale: 5.5).frame(width: 100, height: 100).offset(x: 290, y: -230)
            OutlinedSparkle(color: Brand.lime, lineScale: 5.5).frame(width: 80, height: 80).offset(x: 270, y: 280)
        }
        .frame(width: 1024, height: 1024)
    }

    private func ring(_ half: OrbitRing.Half) -> some View {
        OrbitRing(half: half, lineScale: 5.5).frame(width: 800, height: 230).rotationEffect(.degrees(-12)).offset(
            y: -20)
    }
}

/// Text with an ink outline, a solid ink extrusion down-right, and an italic skew.
struct ChunkyText: View {
    let text: String
    let size: CGFloat
    var fill = Brand.lilac

    var body: some View {
        let glyphs = Text(text).font(.system(size: size, weight: .black, design: .rounded)).kerning(-size * 0.03)
        let outline = size * 0.055
        let depth = size * 0.08
        ZStack {
            ForEach(0..<7) { step in
                Outline(glyphs: glyphs, width: outline).offset(
                    x: depth * CGFloat(step) / 6, y: depth * CGFloat(step) / 6)
            }
            glyphs.foregroundStyle(fill)
            glyphs.foregroundStyle(.white.opacity(0.55)).mask(  // glossy top half
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
        }
        .padding(outline + depth)
        .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: size * 0.14, ty: 0))
    }

    private struct Outline: View {
        let glyphs: Text
        let width: CGFloat

        var body: some View {
            ZStack {
                ForEach(0..<16) { index in
                    let angle = Double(index) / 16 * 2 * .pi
                    glyphs.foregroundStyle(Brand.ink).offset(x: cos(angle) * width, y: sin(angle) * width)
                }
            }
        }
    }
}

/// Black slanted label strip, like the "STREET WEAR" bars in Y2K logos.
struct Banner: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .italic()
            .kerning(size * 0.35)
            .foregroundStyle(Brand.lime)
            .padding(.horizontal, size * 0.9)
            .padding(.vertical, size * 0.3)
            .background(Parallelogram(slant: size * 0.6).fill(Brand.ink))
    }
}

struct Parallelogram: Shape {
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Lime wireframe globe with an ink grid.
struct Globe: View {
    var lineScale: CGFloat = 1

    var body: some View {
        ZStack {
            Circle().fill(Brand.lime)
            GlobeGrid().stroke(Brand.ink, lineWidth: 2.2 * lineScale)
            Circle().strokeBorder(Brand.ink, lineWidth: 4.5 * lineScale)
        }
    }
}

struct GlobeGrid: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for latitude in [-0.66, -0.33, 0, 0.33, 0.66] {  // front halves of tilted latitude circles
            let y = center.y + radius * latitude
            let half = radius * (1 - latitude * latitude).squareRoot()
            let ring = Path(
                ellipseIn: CGRect(x: center.x - half, y: y - half * 0.22, width: 2 * half, height: half * 0.44))
            path.addPath(ring.trimmedPath(from: 0, to: 0.5))
        }
        for width in [0.38, 0.75] {  // meridians
            path.addEllipse(
                in: CGRect(
                    x: center.x - radius * width, y: center.y - radius, width: 2 * radius * width, height: 2 * radius))
        }
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        return path
    }
}

/// Two-tone ring: thick ink stroke with a white core. Draw the back half before the globe and the front half after it.
struct OrbitRing: View {
    enum Half { case back, front }

    let half: Half
    var lineScale: CGFloat = 1

    var body: some View {
        // Ellipse paths start at 3 o'clock and run clockwise on screen, so 0...0.5 is the lower (front) half.
        let range: ClosedRange<CGFloat> = half == .front ? 0...0.5 : 0.5...1
        ZStack {
            Ellipse().trim(from: range.lowerBound, to: range.upperBound)
                .stroke(Brand.ink, style: StrokeStyle(lineWidth: 9 * lineScale, lineCap: .round))
            Ellipse().trim(from: range.lowerBound, to: range.upperBound)
                .stroke(.white, style: StrokeStyle(lineWidth: 3.5 * lineScale, lineCap: .round))
        }
    }
}

/// Four-point star with concave sides.
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let waistX = rect.width * 0.1
        let waistY = rect.height * 0.1
        return Path { path in
            path.move(to: CGPoint(x: center.x, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: center.y), control: CGPoint(x: center.x + waistX, y: center.y - waistY))
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: rect.maxY), control: CGPoint(x: center.x + waistX, y: center.y + waistY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: center.y), control: CGPoint(x: center.x - waistX, y: center.y + waistY))
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: rect.minY), control: CGPoint(x: center.x - waistX, y: center.y - waistY))
            path.closeSubpath()
        }
    }
}

struct OutlinedSparkle: View {
    let color: Color
    var lineScale: CGFloat = 1

    var body: some View {
        ZStack {
            Sparkle().fill(color)
            Sparkle().stroke(Brand.ink, style: StrokeStyle(lineWidth: 2.5 * lineScale, lineJoin: .round))
        }
    }
}
