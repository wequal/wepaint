import CoreGraphics
import UIKit

/// Base class for freehand tools. Subclasses draw segments into the target context; this class
/// handles undo bookkeeping, dirty-rect tracking and scratch compositing.
class StrokeTool: Tool {
    var kind: ToolKind { .pencil }

    var lastPoint: CGPoint = .zero
    var dirty: CGRect = .null
    var isStroking = false
    var strokeStart: TimeInterval = 0

    /// Tools that need uniform transparency along the stroke draw into the scratch bitmap.
    var usesScratch: Bool { false }
    var scratchAlpha: CGFloat { 1 }
    var scratchBlendMode: CGBlendMode { .normal }

    /// How far the drawing can extend around the touch position (for dirty-rect computation).
    func radius(_ ctx: ToolContext) -> CGFloat { ctx.document.strokeWidth / 2 + 2 }

    func targetContext(_ ctx: ToolContext) -> CGContext {
        usesScratch ? ctx.scratch.context : ctx.layer.context
    }

    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        ctx.document.commitFloating()
        ctx.document.beginPixelEdit(on: ctx.layer)
        if usesScratch { ctx.beginScratch(alpha: scratchAlpha, blendMode: scratchBlendMode) }
        isStroking = true
        lastPoint = touch.location
        dirty = .null
        strokeStart = touch.timestamp
        prepare(targetContext(ctx), ctx)
        drawDot(at: touch.location, touch: touch, in: targetContext(ctx), ctx)
        flush(ctx)
    }

    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard isStroking else { return }
        let cg = targetContext(ctx)
        drawSegment(from: lastPoint, to: touch.location, touch: touch, in: cg, ctx)
        lastPoint = touch.location
        flush(ctx)
    }

    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard isStroking else { return }
        if touch.location != lastPoint {
            drawSegment(from: lastPoint, to: touch.location, touch: touch, in: targetContext(ctx), ctx)
        }
        isStroking = false
        if usesScratch {
            ctx.applyScratch()
        }
        ctx.layer.invalidate()
        ctx.document.endPixelEdit(label: label, dirtyRect: dirty.isNull ? .zero : dirty)
    }

    func touchCancelled(_ ctx: ToolContext) {
        guard isStroking else { return }
        isStroking = false
        ctx.discardScratch()
        ctx.document.cancelPixelEdit()
    }

    var label: String { kind.title }

    /// Record and refresh the area touched by the last drawing call.
    func markDirty(_ rect: CGRect, _ ctx: ToolContext) {
        let r = rect.expanded(by: radius(ctx))
        dirty = dirty.isNull ? r : dirty.union(r)
        pendingInvalidate = pendingInvalidate.isNull ? r : pendingInvalidate.union(r)
    }

    private var pendingInvalidate: CGRect = .null

    private func flush(_ ctx: ToolContext) {
        ctx.layer.invalidate()
        if !pendingInvalidate.isNull {
            ctx.invalidate(pendingInvalidate)
            pendingInvalidate = .null
        }
    }

    // MARK: Overridables

    func prepare(_ cg: CGContext, _ ctx: ToolContext) {}

    func drawDot(at p: CGPoint, touch: ToolTouch, in cg: CGContext, _ ctx: ToolContext) {
        drawSegment(from: p, to: p, touch: touch, in: cg, ctx)
    }

    func drawSegment(from a: CGPoint, to b: CGPoint, touch: ToolTouch, in cg: CGContext, _ ctx: ToolContext) {}

    // MARK: Helpers

    func strokeLine(_ cg: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat, color: CGColor, cap: CGLineCap, antialias: Bool, blend: CGBlendMode = .normal) {
        cg.saveGState()
        cg.setShouldAntialias(antialias)
        cg.setBlendMode(blend)
        cg.setLineCap(cap)
        cg.setLineJoin(.round)
        cg.setLineWidth(width)
        cg.setStrokeColor(color)
        cg.move(to: a)
        if a == b { cg.addLine(to: CGPoint(x: b.x + 0.01, y: b.y)) } else { cg.addLine(to: b) }
        cg.strokePath()
        cg.restoreGState()
    }

    /// Calls `stamp` at evenly spaced positions along the segment.
    func stampAlong(from a: CGPoint, to b: CGPoint, spacing: CGFloat, _ stamp: (CGPoint, CGFloat) -> Void) {
        let d = a.distance(to: b)
        if d < 0.01 { stamp(a, 0); return }
        let steps = max(1, Int(d / max(0.5, spacing)))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            stamp(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), t)
        }
    }
}

// MARK: - Pencil

final class PencilTool: StrokeTool {
    override var kind: ToolKind { .pencil }

    override func drawSegment(from a: CGPoint, to b: CGPoint, touch: ToolTouch, in cg: CGContext, _ ctx: ToolContext) {
        let w = max(1, ctx.document.strokeWidth.rounded())
        // Pencil draws hard-edged pixels; snap to pixel centres for 1px lines.
        let off: CGFloat = w.truncatingRemainder(dividingBy: 2) == 1 ? 0.5 : 0
        let pa = CGPoint(x: floor(a.x) + off, y: floor(a.y) + off)
        let pb = CGPoint(x: floor(b.x) + off, y: floor(b.y) + off)
        strokeLine(cg, from: pa, to: pb, width: w, color: ctx.document.primaryColor.cgColor, cap: .square, antialias: false)
        markDirty(CGRect.spanning(pa, pb), ctx)
    }
}

// MARK: - Eraser

final class EraserTool: StrokeTool {
    override var kind: ToolKind { .eraser }

    override func radius(_ ctx: ToolContext) -> CGFloat { ctx.document.strokeWidth + 2 }

    override func drawSegment(from a: CGPoint, to b: CGPoint, touch: ToolTouch, in cg: CGContext, _ ctx: ToolContext) {
        let w = max(2, ctx.document.strokeWidth * 2)
        let color: CGColor = ctx.document.eraseColor?.cgColor ?? CGColor(colorSpace: RasterLayer.colorSpace, components: [0, 0, 0, 0])!
        strokeLine(cg, from: a, to: b, width: w, color: color, cap: .square, antialias: false, blend: .copy)
        markDirty(CGRect.spanning(a, b), ctx)
    }
}

// MARK: - Brushes

final class BrushTool: StrokeTool {
    override var kind: ToolKind { .brush }

    private var brush: BrushKind = .brush
    private var rng = SystemRandomNumberGenerator()

    override var usesScratch: Bool {
        switch brush {
        case .marker, .watercolor: return true
        default: return false
        }
    }

    override var scratchAlpha: CGFloat {
        switch brush {
        case .marker: return 0.55
        case .watercolor: return 0.45
        default: return 1
        }
    }

    override var scratchBlendMode: CGBlendMode {
        brush == .marker ? .multiply : .normal
    }

    override var label: String { brush.title }

    override func radius(_ ctx: ToolContext) -> CGFloat {
        switch brush {
        case .airbrush: return ctx.document.strokeWidth * 2 + 4
        case .watercolor: return ctx.document.strokeWidth * 1.5 + 4
        default: return ctx.document.strokeWidth + 4
        }
    }

    override func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        brush = ctx.document.brushKind
        super.touchBegan(touch, ctx)
    }

    private func pressureWidth(_ base: CGFloat, _ touch: ToolTouch) -> CGFloat {
        touch.isPencil ? max(1, base * (0.4 + 0.8 * touch.force)) : base
    }

    override func drawSegment(from a: CGPoint, to b: CGPoint, touch: ToolTouch, in cg: CGContext, _ ctx: ToolContext) {
        let doc = ctx.document
        let size = max(1, doc.strokeWidth)
        let color = doc.primaryColor
        switch brush {
        case .brush:
            strokeLine(cg, from: a, to: b, width: pressureWidth(size, touch), color: color.cgColor, cap: .round, antialias: true)
        case .calligraphy1, .calligraphy2:
            let angle: CGFloat = brush == .calligraphy1 ? -.pi / 4 : .pi / 4
            let w = pressureWidth(size, touch)
            cg.saveGState()
            cg.setFillColor(color.cgColor)
            stampAlong(from: a, to: b, spacing: max(0.5, w / 6)) { p, _ in
                cg.saveGState()
                cg.translateBy(x: p.x, y: p.y)
                cg.rotate(by: angle)
                cg.fillEllipse(in: CGRect(x: -w / 2, y: -w / 8, width: w, height: max(1, w / 4)))
                cg.restoreGState()
            }
            cg.restoreGState()
        case .airbrush:
            let r = size * 1.5
            let density = Int(max(6, r * r / 8))
            cg.saveGState()
            cg.setFillColor(color.uiColor.withAlphaComponent(0.35).cgColor)
            stampAlong(from: a, to: b, spacing: max(1, r / 3)) { p, _ in
                for _ in 0..<density {
                    let ang = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
                    let dist = sqrt(CGFloat.random(in: 0...1, using: &rng)) * r
                    let q = CGPoint(x: p.x + cos(ang) * dist, y: p.y + sin(ang) * dist)
                    cg.fill(CGRect(x: q.x, y: q.y, width: 1, height: 1))
                }
            }
            cg.restoreGState()
        case .oil:
            let w = pressureWidth(size, touch)
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(0.001, hypot(dx, dy))
            let nx = -dy / len, ny = dx / len
            let bristles = max(3, Int(w / 2))
            for i in 0..<bristles {
                let t = (CGFloat(i) / CGFloat(max(1, bristles - 1)) - 0.5) * w
                let jitter = CGFloat.random(in: -0.6...0.6, using: &rng)
                let off = CGPoint(x: nx * (t + jitter), y: ny * (t + jitter))
                let alpha = CGFloat.random(in: 0.55...1, using: &rng)
                let shade = CGFloat.random(in: -0.08...0.08, using: &rng)
                let c = color.uiColor.adjustedBrightness(by: shade).withAlphaComponent(alpha).cgColor
                strokeLine(cg, from: a.offset(dx: off.x, dy: off.y), to: b.offset(dx: off.x, dy: off.y),
                           width: max(1, w / CGFloat(bristles) * 1.8), color: c, cap: .round, antialias: true)
            }
        case .crayon:
            let w = max(2, size)
            cg.saveGState()
            stampAlong(from: a, to: b, spacing: 1.5) { p, _ in
                let dots = Int(max(4, w * 1.2))
                for _ in 0..<dots {
                    let ang = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
                    let dist = CGFloat.random(in: 0...1, using: &rng) * w / 2
                    let q = CGPoint(x: p.x + cos(ang) * dist, y: p.y + sin(ang) * dist)
                    let s = CGFloat.random(in: 1...2.2, using: &rng)
                    cg.setFillColor(color.uiColor.withAlphaComponent(CGFloat.random(in: 0.35...0.9, using: &rng)).cgColor)
                    cg.fillEllipse(in: CGRect(x: q.x - s / 2, y: q.y - s / 2, width: s, height: s))
                }
            }
            cg.restoreGState()
        case .marker:
            strokeLine(cg, from: a, to: b, width: max(2, size * 1.4), color: color.cgColor, cap: .square, antialias: true)
        case .naturalPencil:
            let w = max(1, size / 2.5)
            cg.saveGState()
            stampAlong(from: a, to: b, spacing: 0.8) { p, _ in
                for _ in 0..<2 {
                    let q = CGPoint(x: p.x + CGFloat.random(in: -w / 2...w / 2, using: &rng),
                                    y: p.y + CGFloat.random(in: -w / 2...w / 2, using: &rng))
                    cg.setFillColor(color.uiColor.withAlphaComponent(CGFloat.random(in: 0.25...0.7, using: &rng)).cgColor)
                    cg.fill(CGRect(x: q.x - 0.5, y: q.y - 0.5, width: 1.2, height: 1.2))
                }
            }
            cg.restoreGState()
        case .watercolor:
            let w = max(3, size * 1.6)
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: w * 0.6, color: color.cgColor)
            cg.setFillColor(color.uiColor.withAlphaComponent(0.9).cgColor)
            stampAlong(from: a, to: b, spacing: max(1, w / 4)) { p, _ in
                cg.fillEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
            }
            cg.restoreGState()
        }
        markDirty(CGRect.spanning(a, b), ctx)
    }
}

extension UIColor {
    func adjustedBrightness(by delta: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: max(0, min(1, b + delta)), alpha: a)
    }
}
