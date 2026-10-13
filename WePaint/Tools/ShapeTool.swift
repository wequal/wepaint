import CoreGraphics
import UIKit

struct PendingShape {
    var kind: ShapeKind
    var rect: CGRect = .zero
    var p1: CGPoint = .zero
    var p2: CGPoint = .zero
    var controls: [CGPoint] = []
    var polygon: [CGPoint] = []
    var polygonClosed = false

    var boundingRect: CGRect {
        switch kind {
        case .line: return CGRect.spanning(p1, p2)
        case .curve: return path.boundingBoxOfPath
        case .polygon: return path.boundingBoxOfPath
        default: return rect
        }
    }

    var path: CGPath {
        let p = CGMutablePath()
        switch kind {
        case .line:
            p.move(to: p1)
            p.addLine(to: p2)
        case .curve:
            p.move(to: p1)
            if controls.count >= 2 {
                p.addCurve(to: p2, control1: controls[0], control2: controls[1])
            } else if controls.count == 1 {
                p.addQuadCurve(to: p2, control: controls[0])
            } else {
                p.addLine(to: p2)
            }
        case .polygon:
            guard let first = polygon.first else { break }
            p.move(to: first)
            for pt in polygon.dropFirst() { p.addLine(to: pt) }
            if polygonClosed { p.closeSubpath() }
        default:
            return ShapePaths.path(for: kind, in: rect)
        }
        return p
    }

    var isClosedShape: Bool {
        switch kind {
        case .line, .curve: return false
        case .polygon: return polygonClosed
        default: return true
        }
    }

    mutating func translate(by d: CGSize) {
        rect = rect.offsetBy(dx: d.width, dy: d.height)
        p1 = p1.offset(dx: d.width, dy: d.height)
        p2 = p2.offset(dx: d.width, dy: d.height)
        controls = controls.map { $0.offset(dx: d.width, dy: d.height) }
        polygon = polygon.map { $0.offset(dx: d.width, dy: d.height) }
    }
}

/// Draws Paint-style shapes. After drawing, a shape stays editable (move/resize) until the user
/// taps outside it, changes tool, or performs another action.
final class ShapeTool: Tool {
    var kind: ToolKind { .shape }

    private enum Drag {
        case draw
        case move(start: CGPoint, original: PendingShape)
        case resize(HandlePosition, original: CGRect)
        case lineEnd(Int)
        case bend(Int)
        case polygonVertex
    }

    private(set) var pending: PendingShape?
    private var drag: Drag?
    private var dragStart: CGPoint = .zero
    private var bendsDone = 0

    var hasPendingWork: Bool { pending != nil }

    // MARK: Touches

    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        let doc = ctx.document
        let p = touch.location
        dragStart = p
        let tol = 12 / ctx.zoom

        if var shape = pending {
            if shape.kind == .polygon, !shape.polygonClosed {
                if shape.polygon.count >= 3, let first = shape.polygon.first, first.distance(to: p) <= tol {
                    shape.polygonClosed = true
                    pending = shape
                    commitPending(ctx)
                    return
                }
                shape.polygon.append(p)
                pending = shape
                drag = .polygonVertex
                ctx.invalidateOverlay()
                return
            }
            if shape.kind == .curve, bendsDone < 2 {
                if shape.controls.count <= bendsDone { shape.controls.append(p) } else { shape.controls[bendsDone] = p }
                pending = shape
                drag = .bend(bendsDone)
                ctx.invalidateOverlay()
                return
            }
            if shape.kind == .line || shape.kind == .curve {
                if shape.p1.distance(to: p) <= tol { drag = .lineEnd(0); return }
                if shape.p2.distance(to: p) <= tol { drag = .lineEnd(1); return }
            } else if shape.kind != .polygon, let h = HandlePosition.hit(p, in: shape.rect, tolerance: tol) {
                drag = .resize(h, original: shape.rect)
                return
            }
            if shape.boundingRect.expanded(by: tol).contains(p) {
                drag = .move(start: p, original: shape)
                return
            }
            commitPending(ctx)
        }

        doc.commitFloating()
        var shape = PendingShape(kind: doc.shapeKind)
        shape.rect = CGRect(origin: p, size: .zero)
        shape.p1 = p
        shape.p2 = p
        if shape.kind == .polygon { shape.polygon = [p, p] }
        pending = shape
        bendsDone = 0
        drag = .draw
        ctx.invalidateOverlay()
    }

    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard var shape = pending, let drag else { return }
        let p = touch.location
        switch drag {
        case .draw:
            shape.rect = CGRect.spanning(dragStart, p)
            shape.p2 = p
            if shape.kind == .polygon, shape.polygon.count >= 2 { shape.polygon[shape.polygon.count - 1] = p }
        case .move(let start, let original):
            shape = original
            shape.translate(by: CGSize(width: p.x - start.x, height: p.y - start.y))
        case .resize(let handle, let original):
            shape.rect = handle.resize(original, to: p)
        case .lineEnd(let i):
            if i == 0 { shape.p1 = p } else { shape.p2 = p }
        case .bend(let i):
            if shape.controls.count > i { shape.controls[i] = p }
        case .polygonVertex:
            if !shape.polygon.isEmpty { shape.polygon[shape.polygon.count - 1] = p }
        }
        pending = shape
        ctx.invalidateOverlay()
    }

    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard var shape = pending, let drag else { return }
        let p = touch.location
        let tol = 12 / ctx.zoom
        defer { self.drag = nil; ctx.invalidateOverlay() }
        switch drag {
        case .draw:
            shape.rect = CGRect.spanning(dragStart, p)
            shape.p2 = p
            if shape.kind == .polygon, shape.polygon.count >= 2 { shape.polygon[shape.polygon.count - 1] = p }
            // Treat small movements as a tap (finger/mouse jitter), independent of zoom, and discard
            // degenerate closed shapes (zero width or height) that would otherwise render as stray lines.
            let tapThreshold = max(2, 10 / ctx.zoom)
            let degenerate = !shape.kind.isOpenPath && (shape.rect.width < 1 || shape.rect.height < 1)
            let tiny = dragStart.distance(to: p) < tapThreshold || degenerate
            if tiny {
                pending = nil
                return
            }
            if shape.kind == .line || shape.kind == .curve { shape.rect = CGRect.spanning(shape.p1, shape.p2) }
            pending = shape
        case .polygonVertex:
            if shape.polygon.count >= 3, let first = shape.polygon.first, first.distance(to: p) <= tol {
                shape.polygon.removeLast()
                shape.polygonClosed = true
                pending = shape
                commitPending(ctx)
                return
            }
            pending = shape
        case .bend(let i):
            bendsDone = i + 1
            pending = shape
            if bendsDone >= 2 { commitPending(ctx) }
        case .move, .resize, .lineEnd:
            pending = shape
        }
    }

    func touchCancelled(_ ctx: ToolContext) {
        if case .draw = drag { pending = nil }
        drag = nil
        ctx.invalidateOverlay()
    }

    // MARK: Pending management

    func commitPending(_ ctx: ToolContext) {
        guard let shape = pending else { return }
        pending = nil
        drag = nil
        let doc = ctx.document
        if shape.kind == .polygon, shape.polygon.count < 2 { ctx.invalidateOverlay(); return }
        doc.beginPixelEdit(on: ctx.layer)
        ShapeTool.render(shape, in: ctx.layer.context, document: doc)
        ctx.layer.invalidate()
        let dirty = shape.path.boundingBoxOfPath.expanded(by: doc.strokeWidth + 2)
        doc.endPixelEdit(label: shape.kind.title, dirtyRect: dirty)
        ctx.invalidateOverlay()
    }

    func cancelPending(_ ctx: ToolContext) {
        pending = nil
        drag = nil
        ctx.invalidateOverlay()
    }

    // MARK: Rendering

    static func render(_ shape: PendingShape, in cg: CGContext, document doc: PaintDocument) {
        let path = shape.path
        cg.saveGState()
        cg.setShouldAntialias(true)
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        if doc.shapeFill == .solid, shape.isClosedShape {
            cg.addPath(path)
            cg.setFillColor(doc.secondaryColor.cgColor)
            cg.fillPath()
        }
        let needsOutline = doc.shapeOutline == .solid || doc.shapeFill == .none || !shape.isClosedShape
        if needsOutline {
            cg.addPath(path)
            cg.setLineWidth(max(1, doc.strokeWidth))
            cg.setStrokeColor(doc.primaryColor.cgColor)
            cg.strokePath()
        }
        cg.restoreGState()
    }

    func drawOverlay(_ cg: CGContext, _ ctx: ToolContext) {
        guard let shape = pending else { return }
        let z = ctx.zoom
        ShapeTool.render(shape, in: cg, document: ctx.document)
        let isDrawing: Bool = { if case .draw = drag { return true } else { return false } }()
        guard !isDrawing else { return }
        switch shape.kind {
        case .line, .curve:
            cg.saveGState()
            if shape.kind == .curve, bendsDone < 2 {
                cg.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.6).cgColor)
                cg.setLineWidth(1 / z)
                cg.setLineDash(phase: 0, lengths: [3 / z, 3 / z])
                for (i, c) in shape.controls.enumerated() {
                    cg.move(to: i == 0 ? shape.p1 : shape.p2)
                    cg.addLine(to: c)
                }
                cg.strokePath()
            }
            cg.restoreGState()
            let r: CGFloat = 8 / z
            cg.saveGState()
            cg.setLineWidth(1 / z)
            for pt in [shape.p1, shape.p2] + shape.controls {
                let hr = CGRect(x: pt.x - r / 2, y: pt.y - r / 2, width: r, height: r)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: hr)
                cg.setStrokeColor(UIColor.systemBlue.cgColor)
                cg.strokeEllipse(in: hr)
            }
            cg.restoreGState()
        case .polygon:
            if !shape.polygonClosed, let first = shape.polygon.first {
                let r: CGFloat = 10 / z
                cg.saveGState()
                cg.setLineWidth(1 / z)
                cg.setStrokeColor(UIColor.systemBlue.cgColor)
                cg.strokeEllipse(in: CGRect(x: first.x - r / 2, y: first.y - r / 2, width: r, height: r))
                cg.restoreGState()
            }
        default:
            OverlayDrawing.drawDashedRect(cg, rect: shape.rect, zoom: z)
            OverlayDrawing.drawHandles(cg, rect: shape.rect, zoom: z)
        }
    }
}
