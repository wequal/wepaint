import CoreGraphics
import UIKit

enum ShapePaths {
    /// Builds a closed/open path for `kind` inside `rect`. Line/curve/polygon are handled by the tool.
    static func path(for kind: ShapeKind, in rect: CGRect) -> CGPath {
        let r = rect.standardized
        let p = CGMutablePath()
        switch kind {
        case .line, .curve, .polygon:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        case .oval:
            p.addEllipse(in: r)
        case .rectangle:
            p.addRect(r)
        case .roundedRectangle:
            let radius = min(r.width, r.height) * 0.18
            p.addRoundedRect(in: r, cornerWidth: radius, cornerHeight: radius)
        case .triangle:
            p.addLines(between: [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
            p.closeSubpath()
        case .rightTriangle:
            p.addLines(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
            p.closeSubpath()
        case .diamond:
            p.addLines(between: [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)])
            p.closeSubpath()
        case .pentagon:
            p.addLines(between: regularPolygon(sides: 5, in: r))
            p.closeSubpath()
        case .hexagon:
            p.addLines(between: regularPolygon(sides: 6, in: r, startAngle: 0))
            p.closeSubpath()
        case .rightArrow:
            p.addLines(between: arrow(in: r))
            p.closeSubpath()
        case .leftArrow:
            p.addLines(between: arrow(in: r).map { CGPoint(x: r.maxX - ($0.x - r.minX), y: $0.y) })
            p.closeSubpath()
        case .upArrow:
            p.addLines(between: arrow(in: CGRect(x: 0, y: 0, width: r.height, height: r.width)).map {
                CGPoint(x: r.minX + $0.y, y: r.maxY - $0.x)
            })
            p.closeSubpath()
        case .downArrow:
            p.addLines(between: arrow(in: CGRect(x: 0, y: 0, width: r.height, height: r.width)).map {
                CGPoint(x: r.minX + $0.y, y: r.minY + $0.x)
            })
            p.closeSubpath()
        case .star4:
            p.addLines(between: star(points: 4, in: r, innerRatio: 0.35))
            p.closeSubpath()
        case .star5:
            p.addLines(between: star(points: 5, in: r, innerRatio: 0.4))
            p.closeSubpath()
        case .star6:
            p.addLines(between: star(points: 6, in: r, innerRatio: 0.55))
            p.closeSubpath()
        case .roundedCallout:
            // Single contour: rounded rectangle body with a tail cut into the bottom edge.
            let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.75)
            let radius = min(body.width, body.height) * 0.2
            let tailBase1 = CGPoint(x: r.minX + r.width * 0.42, y: body.maxY)
            let tailBase2 = CGPoint(x: r.minX + r.width * 0.25, y: body.maxY)
            let tailTip = CGPoint(x: r.minX + r.width * 0.15, y: r.maxY)
            p.move(to: CGPoint(x: body.minX + radius, y: body.minY))
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: radius)
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: radius)
            p.addLine(to: tailBase1)
            p.addLine(to: tailTip)
            p.addLine(to: tailBase2)
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.minY), radius: radius)
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: radius)
            p.closeSubpath()
        case .ovalCallout:
            // Single contour: sampled ellipse with a tail inserted between two angles.
            let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.78)
            let cx = body.midX, cy = body.midY, rx = body.width / 2, ry = body.height / 2
            let tailStart: CGFloat = 100 * .pi / 180, tailEnd: CGFloat = 130 * .pi / 180
            let tailTip = CGPoint(x: r.minX + r.width * 0.15, y: r.maxY)
            let steps = 72
            var started = false
            var inGap = false
            for i in 0..<steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                if a > tailStart, a < tailEnd { inGap = true; continue }
                let pt = CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry)
                if !started { p.move(to: pt); started = true; continue }
                if inGap { p.addLine(to: tailTip); inGap = false }
                p.addLine(to: pt)
            }
            p.closeSubpath()
        case .cloudCallout:
            // Single scalloped contour around an ellipse, plus two small "thought" bubbles.
            let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.72)
            let cx = body.midX, cy = body.midY, rx = body.width / 2 * 0.86, ry = body.height / 2 * 0.82
            let bumps = 11
            var pts: [CGPoint] = []
            for i in 0..<bumps {
                let a = CGFloat(i) / CGFloat(bumps) * 2 * .pi
                pts.append(CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry))
            }
            p.move(to: pts[0])
            for i in 0..<bumps {
                let a = pts[i], b = pts[(i + 1) % bumps]
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let dx = mid.x - cx, dy = mid.y - cy
                let len = max(0.001, hypot(dx, dy))
                let bulge = min(rx, ry) * 0.45
                let control = CGPoint(x: mid.x + dx / len * bulge, y: mid.y + dy / len * bulge)
                p.addQuadCurve(to: b, control: control)
            }
            p.closeSubpath()
            let d1 = min(r.width, r.height) * 0.07
            let d2 = d1 * 0.6
            p.addEllipse(in: CGRect(x: r.minX + r.width * 0.22 - d1, y: body.maxY + (r.maxY - body.maxY) * 0.3 - d1, width: d1 * 2, height: d1 * 2))
            p.addEllipse(in: CGRect(x: r.minX + r.width * 0.12 - d2, y: r.maxY - d2 * 2, width: d2 * 2, height: d2 * 2))
        case .heart:
            let w = r.width, h = r.height
            p.move(to: CGPoint(x: r.midX, y: r.maxY))
            p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.3),
                       control1: CGPoint(x: r.midX - w * 0.1, y: r.minY + h * 0.85),
                       control2: CGPoint(x: r.minX, y: r.minY + h * 0.6))
            p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.3), radius: w * 0.25,
                     startAngle: .pi, endAngle: 0, clockwise: false)
            p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.3), radius: w * 0.25,
                     startAngle: .pi, endAngle: 0, clockwise: false)
            p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                       control1: CGPoint(x: r.maxX, y: r.minY + h * 0.6),
                       control2: CGPoint(x: r.midX + w * 0.1, y: r.minY + h * 0.85))
            p.closeSubpath()
        case .lightning:
            let pts: [(CGFloat, CGFloat)] = [
                (0.45, 0.0), (0.05, 0.55), (0.4, 0.55), (0.25, 1.0), (0.95, 0.4), (0.55, 0.4), (0.8, 0.0),
            ]
            p.addLines(between: pts.map { CGPoint(x: r.minX + r.width * $0.0, y: r.minY + r.height * $0.1) })
            p.closeSubpath()
        }
        return p
    }

    static func regularPolygon(sides: Int, in r: CGRect, startAngle: CGFloat = -.pi / 2) -> [CGPoint] {
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        return (0..<sides).map { i in
            let a = startAngle + CGFloat(i) * 2 * .pi / CGFloat(sides)
            return CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry)
        }
    }

    static func star(points: Int, in r: CGRect, innerRatio: CGFloat) -> [CGPoint] {
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        var pts: [CGPoint] = []
        for i in 0..<(points * 2) {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let k: CGFloat = i % 2 == 0 ? 1 : innerRatio
            pts.append(CGPoint(x: cx + cos(a) * rx * k, y: cy + sin(a) * ry * k))
        }
        return pts
    }

    /// Right-pointing arrow filling `r`.
    static func arrow(in r: CGRect) -> [CGPoint] {
        let headW = r.width * 0.4
        let shaftH = r.height * 0.5
        let shaftTop = r.midY - shaftH / 2, shaftBottom = r.midY + shaftH / 2
        let headX = r.maxX - headW
        return [
            CGPoint(x: r.minX, y: shaftTop), CGPoint(x: headX, y: shaftTop), CGPoint(x: headX, y: r.minY),
            CGPoint(x: r.maxX, y: r.midY), CGPoint(x: headX, y: r.maxY), CGPoint(x: headX, y: shaftBottom),
            CGPoint(x: r.minX, y: shaftBottom),
        ]
    }
}
