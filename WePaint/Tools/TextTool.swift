import CoreGraphics
import UIKit

/// Places an editable text box; the text is rasterised when committed.
final class TextTool: Tool {
    var kind: ToolKind { .text }

    private enum Drag { case create, move(last: CGPoint), resize }
    private var drag: Drag?
    private var start: CGPoint = .zero
    private var previewRect: CGRect?

    var hasPendingWork: Bool { false } // the document's textEditing state tracks pending text

    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        let doc = ctx.document
        let p = touch.location
        start = p
        let tol = 14 / ctx.zoom
        if let editing = doc.textEditing {
            let box = CGRect(origin: editing.origin, size: editing.size)
            let corner = CGPoint(x: box.maxX, y: box.maxY)
            if corner.distance(to: p) <= tol {
                drag = .resize
                return
            }
            if box.expanded(by: tol).contains(p) {
                drag = .move(last: p)
                return
            }
            commitPending(ctx)
        }
        doc.commitFloating()
        drag = .create
        previewRect = nil
    }

    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard let drag else { return }
        let doc = ctx.document
        let p = touch.location
        switch drag {
        case .create:
            previewRect = CGRect.spanning(start, p)
            ctx.invalidateOverlay()
        case .move(let last):
            guard var e = doc.textEditing else { return }
            e.origin = e.origin.offset(dx: p.x - last.x, dy: p.y - last.y)
            doc.textEditing = e
            self.drag = .move(last: p)
        case .resize:
            guard var e = doc.textEditing else { return }
            e.size = CGSize(width: max(40, p.x - e.origin.x), height: max(24, p.y - e.origin.y))
            doc.textEditing = e
        }
    }

    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard let drag else { return }
        let doc = ctx.document
        let p = touch.location
        defer { self.drag = nil; previewRect = nil; ctx.invalidateOverlay() }
        switch drag {
        case .create:
            var r = CGRect.spanning(start, p)
            if r.width < 20 || r.height < 12 {
                let canvas = doc.canvasRect
                let defaultW = min(max(160, doc.textStyle.fontSize * 8), max(40, canvas.maxX - start.x))
                let defaultH = min(max(40, doc.textStyle.fontSize * 1.6), max(24, canvas.maxY - start.y))
                r = CGRect(x: start.x, y: start.y, width: defaultW, height: defaultH)
            }
            r.origin = r.origin.rounded
            doc.textEditing = TextEditingState(origin: r.origin, size: r.size, text: "")
        case .move:
            if var e = doc.textEditing {
                e.origin = e.origin.rounded
                doc.textEditing = e
            }
        case .resize:
            break
        }
    }

    func touchCancelled(_ ctx: ToolContext) {
        drag = nil
        previewRect = nil
        ctx.invalidateOverlay()
    }

    func drawOverlay(_ cg: CGContext, _ ctx: ToolContext) {
        if let r = previewRect {
            OverlayDrawing.drawDashedRect(cg, rect: r, zoom: ctx.zoom)
        }
    }

    func commitPending(_ ctx: ToolContext) {
        let doc = ctx.document
        guard let editing = doc.textEditing else { return }
        doc.textEditing = nil
        let text = editing.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        TextTool.rasterize(text: text, in: CGRect(origin: editing.origin, size: editing.size), ctx: ctx)
    }

    func cancelPending(_ ctx: ToolContext) {
        ctx.document.textEditing = nil
    }

    static func rasterize(text: String, in rect: CGRect, ctx: ToolContext) {
        let doc = ctx.document
        let layer = ctx.layer
        doc.beginPixelEdit(on: layer)
        let attrs = doc.textStyle.attributes(color: doc.primaryColor.uiColor,
                                             background: doc.textStyle.opaqueBackground ? doc.secondaryColor.uiColor : nil)
        let attributed = NSAttributedString(string: text, attributes: attrs)
        UIGraphicsPushContext(layer.context)
        layer.context.saveGState()
        layer.context.setShouldAntialias(true)
        layer.context.setShouldSmoothFonts(true)
        if doc.textStyle.opaqueBackground {
            layer.context.setFillColor(doc.secondaryColor.cgColor)
            layer.context.fill(rect)
        }
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        layer.context.restoreGState()
        UIGraphicsPopContext()
        layer.invalidate()
        doc.endPixelEdit(label: "Text", dirtyRect: rect)
    }
}
