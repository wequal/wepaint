import CoreGraphics
import UIKit

struct ToolTouch {
    var location: CGPoint
    /// Normalised pressure 0...1 (1 for finger input).
    var force: CGFloat
    var isPencil: Bool
    var timestamp: TimeInterval
}

/// Everything a tool needs to act on the document and refresh the screen.
final class ToolContext {
    unowned let document: PaintDocument
    unowned let canvas: CanvasView

    /// A scratch bitmap the size of the canvas that stroke tools can paint into. The canvas shows it
    /// above the active layer (with `scratchAlpha`) while `scratchVisible` is true.
    private(set) var scratch: RasterLayer
    var scratchVisible = false
    var scratchAlpha: CGFloat = 1
    var scratchBlendMode: CGBlendMode = .normal

    init(document: PaintDocument, canvas: CanvasView) {
        self.document = document
        self.canvas = canvas
        self.scratch = RasterLayer(width: document.canvasWidth, height: document.canvasHeight, name: "scratch")
    }

    var layer: RasterLayer { document.activeLayer }
    var canvasRect: CGRect { document.canvasRect }
    var zoom: CGFloat { document.zoom }

    func ensureScratchSize() {
        if scratch.width != document.canvasWidth || scratch.height != document.canvasHeight {
            scratch = RasterLayer(width: document.canvasWidth, height: document.canvasHeight, name: "scratch")
        }
    }

    func beginScratch(alpha: CGFloat, blendMode: CGBlendMode = .normal) {
        ensureScratchSize()
        scratch.clear()
        scratchAlpha = alpha
        scratchBlendMode = blendMode
        scratchVisible = true
    }

    /// Composites the scratch bitmap into the active layer and hides it.
    func applyScratch() {
        guard scratchVisible else { return }
        if let img = scratch.image {
            layer.draw(img, in: layer.bounds, alpha: scratchAlpha, blendMode: scratchBlendMode, interpolate: false)
        }
        scratchVisible = false
    }

    func discardScratch() {
        scratchVisible = false
    }

    /// Redraws part (or all) of the canvas pixels.
    func invalidate(_ rect: CGRect? = nil) {
        canvas.invalidateCanvas(rect)
    }

    /// Redraws the overlay (handles, previews, selection outline).
    func invalidateOverlay() {
        canvas.invalidateOverlay()
    }
}

protocol Tool: AnyObject {
    var kind: ToolKind { get }
    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext)
    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext)
    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext)
    func touchCancelled(_ ctx: ToolContext)
    /// Draw in canvas coordinates; the context is already transformed so 1 unit = 1 canvas pixel.
    func drawOverlay(_ cg: CGContext, _ ctx: ToolContext)
    /// Bake any pending (uncommitted) work into pixels.
    func commitPending(_ ctx: ToolContext)
    /// Drop any pending work.
    func cancelPending(_ ctx: ToolContext)
    var hasPendingWork: Bool { get }
}

extension Tool {
    func drawOverlay(_ cg: CGContext, _ ctx: ToolContext) {}
    func commitPending(_ ctx: ToolContext) {}
    func cancelPending(_ ctx: ToolContext) {}
    var hasPendingWork: Bool { false }
}

// MARK: - Geometry helpers shared by tools

extension CGRect {
    static func spanning(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    func expanded(by amount: CGFloat) -> CGRect {
        insetBy(dx: -amount, dy: -amount)
    }
}

extension CGPoint {
    func distance(to p: CGPoint) -> CGFloat {
        hypot(p.x - x, p.y - y)
    }

    func offset(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    var rounded: CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
}

/// Handles around a rectangle for move/resize interactions.
enum HandlePosition: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func point(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    /// Returns `rect` resized so that this handle moves to `p`.
    func resize(_ rect: CGRect, to p: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch self {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    static func hit(_ p: CGPoint, in rect: CGRect, tolerance: CGFloat) -> HandlePosition? {
        allCases.first { $0.point(in: rect).distance(to: p) <= tolerance }
    }
}

enum OverlayDrawing {
    /// Draws a selection outline as marching-ants style dashes (static).
    static func drawAnts(_ cg: CGContext, path: CGPath, zoom: CGFloat) {
        cg.saveGState()
        cg.addPath(path)
        cg.setLineWidth(1 / zoom)
        cg.setStrokeColor(UIColor.white.cgColor)
        cg.strokePath()
        cg.addPath(path)
        cg.setLineDash(phase: 0, lengths: [4 / zoom, 4 / zoom])
        cg.setStrokeColor(UIColor.black.cgColor)
        cg.strokePath()
        cg.restoreGState()
    }

    static func drawHandles(_ cg: CGContext, rect: CGRect, zoom: CGFloat, positions: [HandlePosition] = HandlePosition.allCases) {
        let s = 8 / zoom
        cg.saveGState()
        cg.setLineWidth(1 / zoom)
        for h in positions {
            let p = h.point(in: rect)
            let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(r)
            cg.setStrokeColor(UIColor.systemBlue.cgColor)
            cg.stroke(r)
        }
        cg.restoreGState()
    }

    static func drawDashedRect(_ cg: CGContext, rect: CGRect, zoom: CGFloat) {
        cg.saveGState()
        cg.setLineWidth(1 / zoom)
        cg.setStrokeColor(UIColor.systemBlue.cgColor)
        cg.setLineDash(phase: 0, lengths: [3 / zoom, 3 / zoom])
        cg.stroke(rect)
        cg.restoreGState()
    }
}
