import SwiftUI
import UIKit

// MARK: - Localisation

/// Russian is the source language and doubles as the lookup key; the English table is
/// `en.lproj/Localizable.strings`. SwiftUI text built from a literal localises by itself;
/// anything passed around as a `String` goes through `tr`.
func tr(_ key: String) -> String {
    AppLanguage.shared.bundle.localizedString(forKey: key, value: nil, table: nil)
}
func tr(_ key: String, _ args: CVarArg...) -> String {
    String(format: tr(key), locale: AppLanguage.shared.locale, arguments: args)
}

// MARK: - Palette and type

/// The whole app is two inks on paper, taken straight from the logo: sepia ink
/// `#2b2118` on parchment `#f7f1e2`. Anything in between is the same ink at a
/// lower opacity — there are no other colours.
enum Ink {
    static let paper = Color(red: 247.0 / 255, green: 241.0 / 255, blue: 226.0 / 255)
    static let ink = Color(red: 43.0 / 255, green: 33.0 / 255, blue: 24.0 / 255)
    static let paperUI = UIColor(red: 247.0 / 255, green: 241.0 / 255, blue: 226.0 / 255, alpha: 1)
    static let inkUI = UIColor(red: 43.0 / 255, green: 33.0 / 255, blue: 24.0 / 255, alpha: 1)
    static let faded = ink.opacity(0.62)
}

enum InkWeight { case regular, bold, italic, boldItalic }

extension Font {
    /// Georgia, like the logo's lettering.
    static func ink(_ size: CGFloat, _ weight: InkWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .regular: name = "Georgia"
        case .bold: name = "Georgia-Bold"
        case .italic: name = "Georgia-Italic"
        case .boldItalic: name = "Georgia-BoldItalic"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

extension UIFont {
    static func ink(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "Georgia-Bold" : "Georgia", size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

// MARK: - Deterministic randomness

/// Hand-drawn shapes must not change between redraws (or between launches), so
/// every wobble comes from a seeded generator rather than from `random()`.
struct InkRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
    }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}

enum InkSeed {
    /// Stable across launches, unlike `hashValue`.
    static func of(_ text: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 { h = (h ^ UInt64(byte)) &* 0x100_0000_01B3 }
        return h
    }
}

// MARK: - Wobbling any path

fileprivate struct FlatSubpath {
    var points: [CGPoint]
    var closed: Bool
}

fileprivate extension Path {
    /// Polylines with roughly `step` points between vertices.
    func flattened(step: CGFloat) -> [FlatSubpath] {
        var result: [FlatSubpath] = []
        var current: [CGPoint] = []
        var start = CGPoint.zero
        var last = CGPoint.zero

        func line(to p: CGPoint) {
            let d = hypot(p.x - last.x, p.y - last.y)
            let n = max(1, Int((d / step).rounded(.up)))
            for i in 1...n {
                let t = CGFloat(i) / CGFloat(n)
                current.append(CGPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t))
            }
            last = p
        }

        func quad(to p: CGPoint, control c: CGPoint) {
            let length = hypot(c.x - last.x, c.y - last.y) + hypot(p.x - c.x, p.y - c.y)
            let n = max(2, Int((length / step).rounded(.up)))
            for i in 1...n {
                let t = CGFloat(i) / CGFloat(n)
                let u = 1 - t
                current.append(CGPoint(
                    x: u * u * last.x + 2 * u * t * c.x + t * t * p.x,
                    y: u * u * last.y + 2 * u * t * c.y + t * t * p.y))
            }
            last = p
        }

        func cubic(to p: CGPoint, _ c1: CGPoint, _ c2: CGPoint) {
            let length = hypot(c1.x - last.x, c1.y - last.y)
                + hypot(c2.x - c1.x, c2.y - c1.y)
                + hypot(p.x - c2.x, p.y - c2.y)
            let n = max(3, Int((length / step).rounded(.up)))
            for i in 1...n {
                let t = CGFloat(i) / CGFloat(n)
                let u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                current.append(CGPoint(
                    x: a * last.x + b * c1.x + c * c2.x + d * p.x,
                    y: a * last.y + b * c1.y + c * c2.y + d * p.y))
            }
            last = p
        }

        forEach { element in
            switch element {
            case .move(to: let p):
                if current.count > 1 { result.append(FlatSubpath(points: current, closed: false)) }
                current = [p]
                start = p
                last = p
            case .line(to: let p):
                if current.isEmpty { current = [last] }
                line(to: p)
            case .quadCurve(to: let p, control: let c):
                if current.isEmpty { current = [last] }
                quad(to: p, control: c)
            case .curve(to: let p, control1: let c1, control2: let c2):
                if current.isEmpty { current = [last] }
                cubic(to: p, c1, c2)
            case .closeSubpath:
                if current.count > 1 {
                    if hypot(last.x - start.x, last.y - start.y) > 0.01 { line(to: start) }
                    result.append(FlatSubpath(points: current, closed: true))
                }
                current = []
                last = start
            }
        }
        if current.count > 1 { result.append(FlatSubpath(points: current, closed: false)) }
        return result
    }
}

extension Path {
    /// The same outline drawn by a slightly unsteady hand: every point is pushed
    /// along the local normal by smooth noise of at most `amplitude` points.
    /// Closed outlines use periodic noise so the pen still meets where it began.
    func wobbled(seed: UInt64, amplitude: CGFloat, step: CGFloat = 4) -> Path {
        var out = Path()
        var rng = InkRandom(seed: seed)

        for sub in flattened(step: step) {
            var pts = sub.points
            if sub.closed, pts.count > 2,
               hypot(pts[0].x - pts[pts.count - 1].x, pts[0].y - pts[pts.count - 1].y) < 0.01 {
                pts.removeLast()
            }
            guard pts.count > 1 else { continue }

            var s = [CGFloat](repeating: 0, count: pts.count)
            for i in 1..<pts.count {
                s[i] = s[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            }
            let closingGap = sub.closed
                ? hypot(pts[0].x - pts[pts.count - 1].x, pts[0].y - pts[pts.count - 1].y) : 0
            let total = s[pts.count - 1] + closingGap
            guard total > 0.01 else { continue }

            let phases = (0..<6).map { _ in rng.next() * 2 * .pi }
            func noise(_ at: CGFloat) -> CGFloat {
                if sub.closed {
                    let harmonics: [(k: Double, a: Double)] = [(2, 0.50), (3, 0.42), (5, 0.30), (8, 0.18), (13, 0.10), (21, 0.05)]
                    var sum = 0.0
                    for (i, h) in harmonics.enumerated() {
                        sum += h.a * sin(2 * .pi * h.k * Double(at) / Double(total) + phases[i])
                    }
                    return CGFloat(sum / 1.2)
                } else {
                    let v = 0.55 * sin(Double(at) / 19 + phases[0])
                        + 0.30 * sin(Double(at) / 7.3 + phases[1])
                        + 0.15 * sin(Double(at) / 3.1 + phases[2])
                    return CGFloat(v)
                }
            }

            var moved: [CGPoint] = []
            moved.reserveCapacity(pts.count)
            for i in 0..<pts.count {
                let prev = pts[sub.closed ? (i + pts.count - 1) % pts.count : max(i - 1, 0)]
                let next = pts[sub.closed ? (i + 1) % pts.count : min(i + 1, pts.count - 1)]
                var tx = next.x - prev.x
                var ty = next.y - prev.y
                let length = max(hypot(tx, ty), 0.0001)
                tx /= length
                ty /= length
                let offset = amplitude * noise(s[i])
                moved.append(CGPoint(x: pts[i].x - ty * offset, y: pts[i].y + tx * offset))
            }

            out.move(to: moved[0])
            for p in moved.dropFirst() { out.addLine(to: p) }
            if sub.closed { out.closeSubpath() }
        }
        return out
    }
}

// MARK: - Hand-drawn shapes

struct WobblyRoundedRect: Shape {
    var radius: CGFloat
    var seed: UInt64
    var amplitude: CGFloat = 0.9
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 1, r.height > 1 else { return Path() }
        let base = RoundedRectangle(cornerRadius: min(radius, min(r.width, r.height) / 2), style: .circular).path(in: r)
        return base.wobbled(seed: seed, amplitude: amplitude)
    }
}

struct WobblyCircle: Shape {
    var seed: UInt64
    var amplitude: CGFloat = 0.9
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 1, r.height > 1 else { return Path() }
        return Ellipse().path(in: r).wobbled(seed: seed, amplitude: amplitude)
    }
}

struct WobblyLine: Shape {
    var seed: UInt64
    var amplitude: CGFloat = 0.8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p.wobbled(seed: seed, amplitude: amplitude, step: 5)
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

private func inkStroke(_ width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
}

// MARK: - Hatching

/// Diagonal pen hatching, the same shading the logo uses. Mask it to a shape.
struct HatchFill: View {
    var spacing: CGFloat = 4
    var lineWidth: CGFloat = 1
    var seed: UInt64 = 3

    var body: some View {
        Canvas { context, size in
            var rng = InkRandom(seed: seed)
            var path = Path()
            var d = -size.height
            while d < size.width {
                let j1 = CGFloat(rng.next() - 0.5) * 0.9
                let j2 = CGFloat(rng.next() - 0.5) * 0.9
                path.move(to: CGPoint(x: d + j1, y: 0))
                path.addLine(to: CGPoint(x: d + size.height + j2, y: size.height))
                d += spacing + CGFloat(rng.next() - 0.5) * 0.5
            }
            context.stroke(path, with: .color(Ink.ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Boxes, discs, rules

/// A rounded box outlined twice — once firmly, once faintly and slightly off —
/// the way a pen retraces a line. `innerRing` adds the thin second ring the
/// logo puts inside its thick ones.
struct InkBox: View {
    var radius: CGFloat = 12
    var seed: UInt64 = 1
    var lineWidth: CGFloat = 2
    var fill: Color = .clear
    var innerRing = false

    var body: some View {
        let inset = lineWidth / 2 + 1.5
        ZStack {
            WobblyRoundedRect(radius: radius, seed: seed, amplitude: 0.9, inset: inset).fill(fill)
            WobblyRoundedRect(radius: radius, seed: seed, amplitude: 0.9, inset: inset)
                .stroke(Ink.ink, style: inkStroke(lineWidth))
            WobblyRoundedRect(radius: radius, seed: seed &+ 977, amplitude: 1.3, inset: inset)
                .stroke(Ink.ink.opacity(0.5), style: inkStroke(max(0.6, lineWidth * 0.36)))
            if innerRing {
                WobblyRoundedRect(radius: max(radius - 4, 2), seed: seed &+ 31, amplitude: 0.7, inset: inset + 3.8)
                    .stroke(Ink.ink, style: inkStroke(0.9))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A round dial key: firm ring, thin inner ring, and a hatched shadow that the
/// key sinks into when pressed.
struct InkDisc: View {
    var diameter: CGFloat
    var seed: UInt64 = 1
    var pressed = false
    var lineWidth: CGFloat = 2.4
    var shadow = true

    var body: some View {
        let inset = lineWidth / 2 + 1.5
        ZStack {
            if shadow {
                HatchFill(spacing: 3.4, lineWidth: 1, seed: seed)
                    .frame(width: diameter, height: diameter)
                    .mask(Circle())
                    .offset(x: pressed ? 1 : 3.2, y: pressed ? 1.2 : 3.8)
            }
            ZStack {
                WobblyCircle(seed: seed, amplitude: 0.9, inset: inset).fill(pressed ? Ink.ink : Ink.paper)
                WobblyCircle(seed: seed, amplitude: 0.9, inset: inset).stroke(Ink.ink, style: inkStroke(lineWidth))
                WobblyCircle(seed: seed &+ 977, amplitude: 1.3, inset: inset)
                    .stroke(Ink.ink.opacity(0.5), style: inkStroke(max(0.6, lineWidth * 0.36)))
                WobblyCircle(seed: seed &+ 31, amplitude: 0.7, inset: inset + 4.4)
                    .stroke(pressed ? Ink.paper : Ink.ink, style: inkStroke(0.9))
            }
            .frame(width: diameter, height: diameter)
            .offset(x: pressed ? 2 : 0, y: pressed ? 2.4 : 0)
        }
        .frame(width: diameter + 6, height: diameter + 6)
        .accessibilityHidden(true)
    }
}

/// The logo's sunburst ring: radial bars between thin circles.
struct InkSunburst: View {
    var diameter: CGFloat
    var rays = 26

    var body: some View {
        let radius = diameter / 2
        ZStack {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let rayInner = radius * 0.70
                let rayOuter = radius * 0.905
                var rng = InkRandom(seed: 77)
                var path = Path()
                for i in 0..<rays {
                    let a = (Double(i) + 0.5) / Double(rays) * 2 * .pi + (rng.next() - 0.5) * 0.035
                    let r0 = rayInner + CGFloat(rng.next() - 0.5) * 0.9
                    let r1 = rayOuter + CGFloat(rng.next() - 0.5) * 0.9
                    path.move(to: CGPoint(x: c.x + r0 * CGFloat(cos(a)), y: c.y + r0 * CGFloat(sin(a))))
                    path.addLine(to: CGPoint(x: c.x + r1 * CGFloat(cos(a)), y: c.y + r1 * CGFloat(sin(a))))
                }
                let middle = (rayInner + rayOuter) / 2
                let bar = 2 * .pi * middle / CGFloat(rays) * 0.5
                context.stroke(path, with: .color(Ink.ink), style: StrokeStyle(lineWidth: bar, lineCap: .butt))
            }
            WobblyCircle(seed: 5, amplitude: 0.8, inset: 1.5).stroke(Ink.ink, style: inkStroke(1.2))
            WobblyCircle(seed: 6, amplitude: 0.7, inset: radius * 0.345).stroke(Ink.ink, style: inkStroke(0.9))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// Call and hang-up buttons: the sunburst with a solid disc and a paper-coloured handset.
struct InkSunburstFace: View {
    var diameter: CGFloat
    var glyph: InkGlyph

    var body: some View {
        ZStack {
            InkSunburst(diameter: diameter)
            WobblyCircle(seed: 21, amplitude: 0.8, inset: diameter * 0.21).fill(Ink.ink)
            InkGlyphView(glyph: glyph, size: diameter * 0.32, color: Ink.paper)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The "call" button: the mascot in an inked medallion with a hatched shadow, and a
/// small handset badge so the button still reads as "call" without a label.
struct InkMascotCallFace: View {
    var diameter: CGFloat = 92

    var body: some View {
        // Show the head, the whole beard, the phone and the raised hand: the middle
        // 720 px of the 930 px artwork, shifted a little downwards.
        let medallion = diameter * 0.80
        let k = medallion / 720
        ZStack {
            InkDisc(diameter: diameter, seed: 811, lineWidth: 3)
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 930 * k, height: 930 * k)
                .offset(x: -5 * k, y: 75 * k)
                .frame(width: medallion, height: medallion)
                .clipShape(Circle())
                .overlay(WobblyCircle(seed: 812, amplitude: 0.6, inset: 1).stroke(Ink.ink, style: inkStroke(2.4)))
            ZStack {
                Circle().fill(Ink.ink)
                InkGlyphView(glyph: .handset, size: diameter * 0.22, color: Ink.paper)
            }
            .frame(width: diameter * 0.32, height: diameter * 0.32)
            .overlay(Circle().stroke(Ink.paper, lineWidth: 2))
            .offset(x: diameter * 0.36, y: diameter * 0.36)
        }
        .frame(width: diameter + 6, height: diameter + 6)
        .accessibilityHidden(true)
    }
}

/// A hand-ruled line; `double` adds the thin twin the logo's rings have.
struct InkRule: View {
    var double = false
    var seed: UInt64 = 5

    var body: some View {
        VStack(spacing: 2.2) {
            WobblyLine(seed: seed, amplitude: 0.8)
                .stroke(Ink.ink, style: inkStroke(double ? 1.6 : 0.9))
                .frame(height: 3)
            if double {
                WobblyLine(seed: seed &+ 11, amplitude: 0.6)
                    .stroke(Ink.ink, style: inkStroke(0.7))
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Titles

/// `—— ◆ TITLE ◆ ——`, with optional controls at either end. Both ends reserve
/// the same width so the title stays centred under the logo.
struct InkScreenHeader<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing

    init(title: String, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        // The full row has fixed-width pieces, so with buttons at both ends (a sheet with
        // "Отмена" and "Сохранить") it is wider than the phone and stretches the whole
        // screen. ViewThatFits drops the ornaments instead of overflowing.
        Group {
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    fullRow
                    compactRow
                }
            } else {
                compactRow
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }

    private var fullRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) { trailing.hidden(); leading }.fixedSize()
            WobblyLine(seed: 3, amplitude: 0.7).stroke(Ink.ink, style: inkStroke(1.2)).frame(height: 4)
            Diamond().fill(Ink.ink).frame(width: 8, height: 8)
            Text(tr(title).uppercased())
                .font(.ink(14, .bold, relativeTo: .subheadline))
                .kerning(3)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Ink.ink)
                .accessibilityAddTraits(.isHeader)
            Diamond().fill(Ink.ink).frame(width: 8, height: 8)
            WobblyLine(seed: 4, amplitude: 0.7).stroke(Ink.ink, style: inkStroke(1.2)).frame(height: 4)
            ZStack(alignment: .trailing) { leading.hidden(); trailing }.fixedSize()
        }
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) { trailing.hidden(); leading }.fixedSize()
            Text(tr(title).uppercased())
                .font(.ink(14, .bold, relativeTo: .subheadline))
                .kerning(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            ZStack(alignment: .trailing) { leading.hidden(); trailing }.fixedSize()
        }
    }
}

extension InkScreenHeader where Leading == EmptyView {
    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, leading: { EmptyView() }, trailing: trailing)
    }
}

extension InkScreenHeader where Leading == EmptyView, Trailing == EmptyView {
    init(title: String) {
        self.init(title: title, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

// MARK: - Logo header and status

/// The app's name, lettered like the logo and ruled off on both sides.
struct InkHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            WobblyLine(seed: 1, amplitude: 0.8).stroke(Ink.ink, style: inkStroke(1.6)).frame(height: 4)
            Text("EzerPhone")
                .font(.ink(28, .bold, relativeTo: .title))
                .kerning(1.5)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Ink.ink)
                .accessibilityAddTraits(.isHeader)
            WobblyLine(seed: 2, amplitude: 0.8).stroke(Ink.ink, style: inkStroke(1.6)).frame(height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

/// Registration state without colour: solid = registered, hatched = working,
/// crossed = failed, empty = inactive. A second ring marks the default account.
struct InkStatusMark: View {
    enum Kind { case registered, progress, failed, inactive }

    var kind: Kind
    var size: CGFloat = 20
    var isDefault = false

    var body: some View {
        ZStack {
            WobblyCircle(seed: 11, amplitude: size * 0.03, inset: 1.5)
                .stroke(Ink.ink, style: inkStroke(max(1.4, size * 0.09)))
            if isDefault {
                WobblyCircle(seed: 12, amplitude: size * 0.025, inset: size * 0.17 + 1.5)
                    .stroke(Ink.ink, style: inkStroke(0.8))
            }
            switch kind {
            case .registered:
                Circle().fill(Ink.ink).frame(width: size * 0.4, height: size * 0.4)
            case .progress:
                HatchFill(spacing: 2.4, lineWidth: 0.9)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .mask(Circle())
            case .failed:
                Path { p in
                    let a = size * 0.3, b = size * 0.7
                    p.move(to: CGPoint(x: a, y: a)); p.addLine(to: CGPoint(x: b, y: b))
                    p.move(to: CGPoint(x: b, y: a)); p.addLine(to: CGPoint(x: a, y: b))
                }
                .stroke(Ink.ink, style: inkStroke(max(1.4, size * 0.085)))
            case .inactive:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct InkStatusRow: View {
    var kind: InkStatusMark.Kind
    var text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                InkStatusMark(kind: kind, size: 14)
                Text(text)
                    .font(.ink(12, .italic, relativeTo: .footnote))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            InkRule(double: true, seed: 8)
                .padding(.horizontal, 14)
        }
        .accessibilityElement(children: .combine)
    }
}

struct InkEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                WobblyLine(seed: 14).stroke(Ink.ink, style: inkStroke(1)).frame(height: 4)
                Diamond().fill(Ink.ink).frame(width: 7, height: 7)
                WobblyLine(seed: 15).stroke(Ink.ink, style: inkStroke(1)).frame(height: 4)
            }
            .frame(width: 130)
            Text(tr(text))
                .font(.ink(15, .italic, relativeTo: .callout))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Ink.faded)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
    }
}

// MARK: - Buttons

struct InkPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct InkIconButton: View {
    let glyph: InkGlyph
    let label: String
    var size: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            InkGlyphView(glyph: glyph, size: size)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(tr(label))
    }
}

/// Text control with a pen underline, for "Готово" and friends.
struct InkTextButton: View {
    let title: String
    var bold = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(tr(title))
                    .font(.ink(15, bold ? .boldItalic : .italic, relativeTo: .callout))
                    .foregroundStyle(Ink.ink)
                    .fixedSize()
                WobblyLine(seed: InkSeed.of(title), amplitude: 0.5)
                    .stroke(Ink.ink, style: inkStroke(1))
                    .frame(height: 3)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(InkPressStyle())
    }
}

/// A pill outlined like everything else; pressing fills it with ink.
struct InkWideButton: View {
    let title: String
    var glyph: InkGlyph?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let glyph { InkGlyphView(glyph: glyph, size: 18) }
                Text(tr(title)).font(.ink(16, .bold, relativeTo: .callout))
            }
            .foregroundStyle(Ink.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(InkBox(radius: 24, seed: InkSeed.of(title), lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(InkPressStyle())
    }
}

/// Small ring with a handset in it, the row-level "call" affordance.
struct InkCallMini: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            WobblyCircle(seed: 41, amplitude: 0.6, inset: 1.5).stroke(Ink.ink, style: inkStroke(1.8))
            WobblyCircle(seed: 42, amplitude: 0.5, inset: 1.5 + size * 0.11).stroke(Ink.ink, style: inkStroke(0.8))
            InkGlyphView(glyph: .handset, size: size * 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Switch

/// Drawn switch: a hatched track and a knob that carries the registered mark
/// when on, an empty ring when off.
struct InkSwitch: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            ZStack {
                if isOn {
                    HatchFill(spacing: 3, lineWidth: 0.9)
                        .mask(WobblyRoundedRect(radius: 14, seed: 3, amplitude: 0.5, inset: 3))
                }
                WobblyRoundedRect(radius: 14, seed: 3, amplitude: 0.6, inset: 2)
                    .stroke(Ink.ink, style: inkStroke(1.9))
                WobblyRoundedRect(radius: 14, seed: 90, amplitude: 0.9, inset: 2)
                    .stroke(Ink.ink.opacity(0.5), style: inkStroke(0.7))
            }
            ZStack {
                Circle().fill(Ink.paper).frame(width: 20, height: 20)
                WobblyCircle(seed: 7, amplitude: 0.4, inset: 1).stroke(Ink.ink, style: inkStroke(1.8)).frame(width: 20, height: 20)
                if isOn { Circle().fill(Ink.ink).frame(width: 9, height: 9) }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 52, height: 30)
        .animation(.easeOut(duration: 0.14), value: isOn)
    }
}

struct InkSwitchButton: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            isOn.toggle()
            Haptics.tap()
        } label: {
            InkSwitch(isOn: isOn).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(label))
        .accessibilityValue(tr(isOn ? "включено" : "выключено"))
        .inkToggleTrait()
    }
}

struct InkToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        HStack(spacing: 12) {
            Text(tr(title))
                .font(.ink(16, .regular, relativeTo: .body))
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            InkSwitchButton(isOn: $isOn, label: title)
        }
        .padding(.vertical, 2)
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

// MARK: - Forms

/// A form group: small-caps title, a doubly-ruled box, italic footnote.
struct InkSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(tr(title).uppercased())
                    .font(.ink(12, .bold, relativeTo: .caption))
                    .kerning(2)
                    .foregroundStyle(Ink.ink)
                    .padding(.leading, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(InkBox(radius: 14, seed: InkSeed.of(title ?? "section"), lineWidth: 2.2, innerRing: true))
            if let footer {
                Text(tr(footer))
                    .font(.ink(12, .italic, relativeTo: .footnote))
                    .foregroundStyle(Ink.faded)
                    .padding(.horizontal, 8)
            }
        }
    }
}

struct InkField: View {
    let title: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var capitalizes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tr(title))
                .font(.ink(12, .italic, relativeTo: .caption))
                .foregroundStyle(Ink.faded)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .font(.ink(17, .regular, relativeTo: .body))
            .foregroundStyle(Ink.ink)
            .tint(Ink.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalizes ? .sentences : .never)
            .autocorrectionDisabled()
            .frame(minHeight: 30)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Screen chrome

extension View {
    /// iOS 16.4 and later can paint the sheet's own background; earlier versions
    /// rely on the content's `inkPaper()` alone.
    @ViewBuilder func inkSheetBackground() -> some View {
        if #available(iOS 16.4, *) { presentationBackground(Ink.paper) } else { self }
    }

    /// `onChange` without the iOS 17-only two-value closure.
    func inkOnChange<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View {
        onChange(of: value) { newValue in action(newValue) }
    }

    @ViewBuilder func inkDismissesKeyboard() -> some View {
        if #available(iOS 16.0, *) { scrollDismissesKeyboard(.interactively) } else { self }
    }

    @ViewBuilder func inkToggleTrait() -> some View {
        if #available(iOS 17.0, *) { accessibilityAddTraits(.isToggle) } else { self }
    }

    /// Parchment behind everything, including under the status bar and home indicator.
    func inkPaper() -> some View {
        background(Ink.paper.ignoresSafeArea())
    }

    /// Plain list on paper: no system background, separators or row chrome.
    @ViewBuilder func inkList() -> some View {
        if #available(iOS 16.0, *) {
            listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Ink.paper)
        } else {
            // iOS 15 has no way to hide a List's background per view; SipPhoneApp clears
            // UITableView's background globally instead.
            listStyle(.plain)
                .background(Ink.paper)
        }
    }

    @ViewBuilder func inkBouncesOnlyWhenNeeded() -> some View {
        if #available(iOS 16.4, *) { scrollBounceBehavior(.basedOnSize) } else { self }
    }

    func inkRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
    }
}
