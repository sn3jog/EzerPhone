import SwiftUI

/// Icons drawn in a 24-unit box and inked with the same unsteady hand as the
/// rest of the app. They replace SF Symbols, which no amount of tinting makes
/// look drawn.
enum InkGlyph: String {
    case star, starFilled, clock, person, keypad
    case handset, handsetDown
    case backspace, plus, trash, sync, check
    case chevronUp, chevronDown, chevronUpDown
    case mic, micOff, speaker, speakerWaves
    case arrowOut, arrowIn, arrowMissed
}

struct InkGlyphPaths {
    var stroke = Path()
    var fill = Path()
    var dashed = false
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func polyline(_ points: [CGPoint], close: Bool = false) -> Path {
    var p = Path()
    guard let first = points.first else { return p }
    p.move(to: first)
    for pt in points.dropFirst() { p.addLine(to: pt) }
    if close { p.closeSubpath() }
    return p
}

/// Clockwise-on-screen arc as a polyline, angles in degrees measured from +x.
private func arcPath(center: CGPoint, radius: CGFloat, from a0: CGFloat, to a1: CGFloat) -> Path {
    let steps = max(4, Int(abs(a1 - a0) / 8))
    var pts: [CGPoint] = []
    for i in 0...steps {
        let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)) * .pi / 180
        pts.append(point(center.x + radius * cos(a), center.y + radius * sin(a)))
    }
    return polyline(pts)
}

private func arrowHead(at tip: CGPoint, direction degrees: CGFloat, size: CGFloat = 3.6) -> Path {
    let back = (degrees + 180) * .pi / 180
    let spread: CGFloat = 32 * .pi / 180
    return polyline([
        point(tip.x + size * cos(back - spread), tip.y + size * sin(back - spread)),
        tip,
        point(tip.x + size * cos(back + spread), tip.y + size * sin(back + spread))
    ])
}

private func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> Path {
    var pts: [CGPoint] = []
    for i in 0..<10 {
        let a = (-90 + 36 * CGFloat(i)) * .pi / 180
        let r = i.isMultiple(of: 2) ? outer : inner
        pts.append(point(center.x + r * cos(a), center.y + r * sin(a)))
    }
    return polyline(pts, close: true)
}

/// Two cups joined by a curved band — the handset from the logo, solid ink.
private func handsetPath(rotation degrees: CGFloat) -> Path {
    var p = Path()
    p.addPath(Path(roundedRect: CGRect(x: 2.8, y: 4.4, width: 6.4, height: 6.6), cornerRadius: 1.9))
    p.addPath(Path(roundedRect: CGRect(x: 14.8, y: 4.4, width: 6.4, height: 6.6), cornerRadius: 1.9))
    var band = Path()
    band.move(to: point(5.2, 10.2))
    band.addQuadCurve(to: point(18.8, 10.2), control: point(12, 19.8))
    band.addLine(to: point(18.8, 13.6))
    band.addQuadCurve(to: point(5.2, 13.6), control: point(12, 23.4))
    band.closeSubpath()
    p.addPath(band)
    let t = CGAffineTransform(translationX: 12, y: 12)
        .rotated(by: degrees * .pi / 180)
        .translatedBy(x: -12, y: -11.6)
    return p.applying(t)
}

extension InkGlyph {
    var paths: InkGlyphPaths {
        var g = InkGlyphPaths()
        switch self {
        case .star, .starFilled:
            let s = starPath(center: point(12, 12.7), outer: 9.8, inner: 4.2)
            g.stroke = s
            if self == .starFilled { g.fill = s }

        case .clock:
            g.stroke.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            g.stroke.addPath(polyline([point(12, 7.2), point(12, 12), point(15.6, 14.2)]))

        case .person:
            g.stroke.addEllipse(in: CGRect(x: 8.1, y: 4.3, width: 7.8, height: 7.8))
            var shoulders = Path()
            shoulders.move(to: point(4.8, 20.5))
            shoulders.addQuadCurve(to: point(19.2, 20.5), control: point(12, 9.5))
            g.stroke.addPath(shoulders)

        case .keypad:
            for row in 0..<3 {
                for col in 0..<3 {
                    let cx = 6 + CGFloat(col) * 6, cy = 6 + CGFloat(row) * 6
                    g.fill.addEllipse(in: CGRect(x: cx - 1.7, y: cy - 1.7, width: 3.4, height: 3.4))
                }
            }

        case .handset:
            g.fill = handsetPath(rotation: 45)
        case .handsetDown:
            g.fill = handsetPath(rotation: 180)

        case .backspace:
            var body = Path()
            body.move(to: point(8.6, 5.8))
            body.addLine(to: point(20.4, 5.8))
            body.addQuadCurve(to: point(21.8, 7.2), control: point(21.8, 5.8))
            body.addLine(to: point(21.8, 16.8))
            body.addQuadCurve(to: point(20.4, 18.2), control: point(21.8, 18.2))
            body.addLine(to: point(8.6, 18.2))
            body.addLine(to: point(2.4, 12))
            body.closeSubpath()
            g.stroke = body
            g.stroke.addPath(polyline([point(12.6, 9.4), point(17.8, 14.6)]))
            g.stroke.addPath(polyline([point(17.8, 9.4), point(12.6, 14.6)]))

        case .plus:
            g.stroke.addPath(polyline([point(12, 4.8), point(12, 19.2)]))
            g.stroke.addPath(polyline([point(4.8, 12), point(19.2, 12)]))

        case .trash:
            g.stroke.addPath(polyline([point(4.5, 7), point(19.5, 7)]))
            g.stroke.addPath(polyline([point(9.2, 7), point(9.2, 4.6), point(14.8, 4.6), point(14.8, 7)]))
            g.stroke.addPath(polyline([point(6.4, 7), point(7.4, 19.8), point(16.6, 19.8), point(17.6, 7)]))
            g.stroke.addPath(polyline([point(10.2, 10.8), point(10.2, 16.4)]))
            g.stroke.addPath(polyline([point(13.8, 10.8), point(13.8, 16.4)]))

        case .sync:
            g.stroke.addPath(arcPath(center: point(12, 12), radius: 7.6, from: 195, to: 318))
            g.stroke.addPath(arrowHead(at: point(12 + 7.6 * cos(318 * .pi / 180), 12 + 7.6 * sin(318 * .pi / 180)), direction: 318 + 90))
            g.stroke.addPath(arcPath(center: point(12, 12), radius: 7.6, from: 15, to: 138))
            g.stroke.addPath(arrowHead(at: point(12 + 7.6 * cos(138 * .pi / 180), 12 + 7.6 * sin(138 * .pi / 180)), direction: 138 + 90))

        case .check:
            g.stroke = polyline([point(5.2, 12.6), point(10, 17.2), point(18.8, 6.8)])

        case .chevronUp:
            g.stroke = polyline([point(6.5, 14.6), point(12, 9.2), point(17.5, 14.6)])
        case .chevronDown:
            g.stroke = polyline([point(6.5, 9.4), point(12, 14.8), point(17.5, 9.4)])
        case .chevronUpDown:
            g.stroke.addPath(polyline([point(8, 9.6), point(12, 5.6), point(16, 9.6)]))
            g.stroke.addPath(polyline([point(8, 14.4), point(12, 18.4), point(16, 14.4)]))

        case .mic, .micOff:
            g.stroke.addRoundedRect(in: CGRect(x: 9, y: 3.2, width: 6, height: 11), cornerSize: CGSize(width: 3, height: 3))
            var holder = Path()
            holder.move(to: point(6.2, 11.2))
            holder.addQuadCurve(to: point(12, 17.6), control: point(6.2, 17.6))
            holder.addQuadCurve(to: point(17.8, 11.2), control: point(17.8, 17.6))
            g.stroke.addPath(holder)
            g.stroke.addPath(polyline([point(12, 17.6), point(12, 21)]))
            g.stroke.addPath(polyline([point(8.8, 21), point(15.2, 21)]))
            if self == .micOff { g.stroke.addPath(polyline([point(4.2, 4.2), point(19.8, 19.8)])) }

        case .speaker, .speakerWaves:
            g.stroke = polyline([point(3.8, 9.6), point(7.6, 9.6), point(12.6, 5.4), point(12.6, 18.6), point(7.6, 14.4), point(3.8, 14.4)], close: true)
            if self == .speakerWaves {
                var w1 = Path()
                w1.move(to: point(15.6, 9.2))
                w1.addQuadCurve(to: point(15.6, 14.8), control: point(17.8, 12))
                var w2 = Path()
                w2.move(to: point(18.4, 6.4))
                w2.addQuadCurve(to: point(18.4, 17.6), control: point(23, 12))
                g.stroke.addPath(w1)
                g.stroke.addPath(w2)
            }

        case .arrowOut:
            g.stroke.addPath(polyline([point(6.5, 17.5), point(17.5, 6.5)]))
            g.stroke.addPath(polyline([point(9.5, 6.5), point(17.5, 6.5), point(17.5, 14.5)]))
        case .arrowIn, .arrowMissed:
            g.stroke.addPath(polyline([point(17.5, 6.5), point(6.5, 17.5)]))
            g.stroke.addPath(polyline([point(6.5, 9.5), point(6.5, 17.5), point(14.5, 17.5)]))
            g.dashed = self == .arrowMissed
        }
        return g
    }
}

private struct GlyphShape: Shape {
    enum Part { case stroke, fill }
    let glyph: InkGlyph
    let part: Part

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let source = part == .stroke ? glyph.paths.stroke : glyph.paths.fill
        guard !source.isEmpty else { return Path() }
        let scaled = source.applying(CGAffineTransform(scaleX: scale, y: scale))
        return scaled.wobbled(seed: InkSeed.of(glyph.rawValue), amplitude: 0.42 * scale, step: max(1.2, 1.6 * scale))
    }
}

struct InkGlyphView: View {
    let glyph: InkGlyph
    var size: CGFloat = 24
    var color: Color = Ink.ink
    var lineWidth: CGFloat?

    var body: some View {
        let lw = lineWidth ?? max(1.3, size / 24 * 1.75)
        ZStack {
            GlyphShape(glyph: glyph, part: .fill).fill(color)
            GlyphShape(glyph: glyph, part: .stroke)
                .stroke(color, style: StrokeStyle(
                    lineWidth: lw, lineCap: .round, lineJoin: .round,
                    dash: glyph.paths.dashed ? [lw * 1.4, lw * 1.2] : []))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
