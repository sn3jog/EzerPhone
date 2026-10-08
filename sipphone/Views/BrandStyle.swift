import SwiftUI
import UIKit

enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .medium)

    static func prepare() {
        generator.prepare()
    }

    static func tap() {
        generator.impactOccurred(intensity: 1.0)
        generator.prepare()
    }
}

enum GearIconFactory {
    static func makeIcon(size: CGFloat = 24) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let scale = size / 24.0
            cg.scaleBy(x: scale, y: scale)
            let center = CGPoint(x: 12, y: 12)

            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(0.6)
            let tri1: [CGPoint] = [CGPoint(x: 12, y: 3), CGPoint(x: 19.79, y: 16.5), CGPoint(x: 4.21, y: 16.5)]
            let tri2: [CGPoint] = [CGPoint(x: 19.79, y: 7.5), CGPoint(x: 12, y: 21), CGPoint(x: 4.21, y: 7.5)]
            for tri in [tri1, tri2] {
                cg.move(to: tri[0])
                cg.addLine(to: tri[1])
                cg.addLine(to: tri[2])
                cg.closePath()
            }
            cg.strokePath()

            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: CGRect(x: center.x - 6.5, y: center.y - 6.5, width: 13, height: 13))

            for i in 0..<6 {
                let angle = CGFloat(i) * (.pi / 3)
                cg.saveGState()
                cg.translateBy(x: center.x, y: center.y)
                cg.rotate(by: angle)
                cg.translateBy(x: -center.x, y: -center.y)
                let rect = CGRect(x: 10, y: 1.3, width: 4, height: 3.2)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 1)
                UIColor.black.setFill()
                path.fill()
                cg.restoreGState()
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
