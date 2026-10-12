import CoreGraphics
import UIKit

/// Rectangle and free-form selection with move/resize of the lifted pixels.
final class SelectTool: Tool {
    var kind: ToolKind { .select }

    private enum Drag {
        case marquee
        case lasso
        case move(last: CGPoint)
        case resize(HandlePosition, original: CGRect)
    }

    private var drag: Drag?
    private var start: CGPoint = .zero
    private var marqueeRect: CGRect?
    private var lassoPoints: [CGPoint] = []

    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        let doc = ctx.document
        let p = touch.location
        start = p
        let tol = 12 / ctx.zoom

        if let f = doc.floating {
            if let h = HandlePosition.hit(p, in: f.frame, tolerance: tol) {
                drag = .resize(h, original: f.frame)
                return
            }
            if f.frame.expanded(by: tol / 2).contains(p) {
                drag = .move(last: p)
                return
            }
            doc.commitFloating()
            doc.selection = nil
        } else if let sel = doc.selection, sel.contains(p) {
            if doc.liftSelection() {
                drag = .move(last: p)
                return
            }
        } else if doc.selection != nil {
            doc.selection = nil
        }

        switch doc.selectMode {
        case .rectangle:
            drag = .marquee
            marqueeRect = CGRect(origin: p, size: .zero)
        case .freeform:
            drag = .lasso
            lassoPoints = [p]
        }
        ctx.invalidateOverlay()
    }

    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard let drag else { return }
        let p = touch.location
        let doc = ctx.document
        switch drag {
        case .marquee:
            marqueeRect = CGRect.spanning(start, p).integral.intersection(doc.canvasRect)
        case .lasso:
            if let last = lassoPoints.last, last.distance(to: p) >= 0.5 { lassoPoints.append(p) }
        case .move(let last):
            doc.moveFloating(by: CGSize(width: (p.x - last.x), height: (p.y - last.y)))
            self.drag = .move(last: p)
        case .resize(let h, let original):
            var r = h.resize(original, to: p)
            r.size.width = max(1, r.width)
            r.size.height = max(1, r.height)
            doc.setFloatingFrame(r)
        }
        ctx.invalidateOverlay()
    }

    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard let drag else { return }
        let doc = ctx.document
        let p = touch.location
        defer { self.drag = nil; marqueeRect = nil; lassoPoints = []; ctx.invalidateOverlay() }
        switch drag {
        case .marquee:
            let r = CGRect.spanning(start, p).integral.intersection(doc.canvasRect)
            if r.width >= 1, r.height >= 1 {
                doc.selection = Selection.rect(r)
            } else {
                doc.selection = nil
            }
        case .lasso:
            lassoPoints.append(p)
            if lassoPoints.count >= 3 {
                let path = CGMutablePath()
                path.addLines(between: lassoPoints)
                path.closeSubpath()
                let sel = Selection(path: path)
                doc.selection = sel.integralBounds(in: doc.canvasRect).isEmpty ? nil : sel
            } else {
                doc.selection = nil
            }
        case .move:
            if var f = doc.floating {
                f.frame.origin = f.frame.origin.rounded
                doc.floating = f
            }
        case .resize:
            if var f = doc.floating {
                f.frame = f.frame.integral
                doc.floating = f
            }
        }
        doc.bumpRender()
    }

    func touchCancelled(_ ctx: ToolContext) {
        drag = nil
        marqueeRect = nil
        lassoPoints = []
        ctx.invalidateOverlay()
    }

    func drawOverlay(_ cg: CGContext, _ ctx: ToolContext) {
        let z = ctx.zoom
        if let r = marqueeRect {
            OverlayDrawing.drawAnts(cg, path: CGPath(rect: r, transform: nil), zoom: z)
        }
        if lassoPoints.count >= 2 {
            let path = CGMutablePath()
            path.addLines(between: lassoPoints)
            OverlayDrawing.drawAnts(cg, path: path, zoom: z)
        }
        if let f = ctx.document.floating {
            OverlayDrawing.drawHandles(cg, rect: f.frame, zoom: z)
        }
    }
}
