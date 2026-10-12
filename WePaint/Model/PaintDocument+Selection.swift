import CoreGraphics
import UIKit

extension PaintDocument {
    // MARK: - Creating / clearing selections

    func setSelection(_ sel: Selection?) {
        commitFloating()
        if let sel, sel.integralBounds(in: canvasRect).isEmpty {
            selection = nil
        } else {
            selection = sel
        }
        bumpRender()
    }

    func selectAll() {
        toolHost?.commitPendingToolWork()
        setSelection(.rect(canvasRect))
        if activeTool != .select { activeTool = .select }
    }

    func deselect() {
        commitFloating()
        selection = nil
        bumpRender()
    }

    func invertSelection() {
        commitFloating()
        guard let sel = selection else {
            selection = nil
            return
        }
        selection = sel.inverted(in: canvasRect)
        bumpRender()
    }

    // MARK: - Extracting pixels

    /// Returns the pixels of `layer` under `selection`, masked to its shape, along with the integral bounds.
    func extractImage(from layer: RasterLayer, selection: Selection, transparent: Bool) -> (CGImage, CGRect, CGPath)? {
        let bounds = selection.integralBounds(in: canvasRect)
        guard bounds.width >= 1, bounds.height >= 1, let source = layer.image else { return nil }
        let temp = RasterLayer(width: Int(bounds.width), height: Int(bounds.height), name: "temp")
        var t = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        let localPath = selection.path.copy(using: &t) ?? selection.path
        temp.context.saveGState()
        temp.context.addPath(localPath)
        temp.context.clip(using: .evenOdd)
        temp.context.drawUpright(source, in: CGRect(x: -bounds.minX, y: -bounds.minY, width: CGFloat(layer.width), height: CGFloat(layer.height)))
        temp.context.restoreGState()
        if transparent {
            let key = secondaryColor.premultipliedBytes
            let n = temp.width * temp.height
            for i in 0..<n {
                let p = i * 4
                if temp.data[p] == key.0, temp.data[p + 1] == key.1, temp.data[p + 2] == key.2, temp.data[p + 3] == key.3 {
                    temp.data[p] = 0; temp.data[p + 1] = 0; temp.data[p + 2] = 0; temp.data[p + 3] = 0
                }
            }
        }
        temp.invalidate()
        guard let img = temp.image else { return nil }
        return (img, bounds, localPath)
    }

    /// Clears the pixels of `layer` under `path` (to transparent, or to the erase color on the background layer).
    func clearRegion(_ path: CGPath, on layer: RasterLayer) {
        let ctx = layer.context
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
        ctx.setBlendMode(.copy)
        if let c = eraseColor {
            ctx.setFillColor(c.cgColor)
        } else {
            ctx.setFillColor(CGColor(colorSpace: RasterLayer.colorSpace, components: [0, 0, 0, 0])!)
        }
        ctx.fill(layer.bounds)
        ctx.restoreGState()
        layer.invalidate()
    }

    // MARK: - Floating selections

    /// Lifts the current selection off the active layer so it can be moved. Returns false if nothing to lift.
    @discardableResult
    func liftSelection() -> Bool {
        guard floating == nil, let sel = selection else { return floating != nil }
        let layer = activeLayer
        guard let (img, bounds, localPath) = extractImage(from: layer, selection: sel, transparent: transparentSelection) else { return false }
        beginPixelEdit(on: layer)
        clearRegion(sel.path, on: layer)
        floating = FloatingSelection(image: img, frame: bounds, localPath: localPath, originalFrame: bounds)
        selection = nil
        bumpRender()
        return true
    }

    /// Places `image` as a new floating selection (paste / import).
    func placeFloating(image: CGImage, at origin: CGPoint) {
        toolHost?.commitPendingToolWork()
        commitFloating()
        selection = nil
        let w = CGFloat(image.width), h = CGFloat(image.height)
        var frame = CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: w, height: h)
        frame.origin.x = max(0, min(frame.origin.x, CGFloat(canvasWidth) - min(w, CGFloat(canvasWidth))))
        frame.origin.y = max(0, min(frame.origin.y, CGFloat(canvasHeight) - min(h, CGFloat(canvasHeight))))
        beginPixelEdit(on: activeLayer)
        floating = FloatingSelection(image: image, frame: frame,
                                     localPath: CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h), transform: nil),
                                     originalFrame: frame)
        if activeTool != .select { activeTool = .select }
        bumpRender()
    }

    /// Bakes the floating pixels into the active layer and leaves a plain selection outline behind.
    func commitFloating() {
        guard let f = floating else { return }
        let layer = activeLayer
        layer.draw(f.image, in: f.frame, interpolate: true)
        floating = nil
        selection = Selection(path: f.canvasPath)
        endPixelEdit(label: "Move selection", dirtyRect: f.frame.union(f.originalFrame))
    }

    func moveFloating(by delta: CGSize) {
        guard var f = floating else { return }
        f.frame.origin.x += delta.width
        f.frame.origin.y += delta.height
        floating = f
        invalidate(nil)
    }

    func setFloatingFrame(_ frame: CGRect) {
        guard var f = floating else { return }
        f.frame = frame.standardized
        floating = f
        invalidate(nil)
    }

    // MARK: - Clipboard operations

    var canPaste: Bool {
        UIPasteboard.general.hasImages
    }

    func copySelection() {
        toolHost?.commitPendingToolWork()
        let image: CGImage?
        if let f = floating {
            image = f.image
        } else if let sel = selection {
            image = extractImage(from: activeLayer, selection: sel, transparent: false)?.0
        } else {
            image = flattenedImage()
        }
        guard let image else { return }
        UIPasteboard.general.image = UIImage(cgImage: image)
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    func deleteSelection() {
        toolHost?.commitPendingToolWork()
        if let f = floating {
            // Discard the floating pixels; the hole left behind is the result.
            floating = nil
            selection = Selection(path: f.canvasPath)
            endPixelEdit(label: "Delete", dirtyRect: f.originalFrame)
            return
        }
        guard let sel = selection else { return }
        let layer = activeLayer
        beginPixelEdit(on: layer)
        clearRegion(sel.path, on: layer)
        endPixelEdit(label: "Delete", dirtyRect: sel.integralBounds(in: canvasRect))
    }

    func paste(at origin: CGPoint = .zero) {
        guard let ui = UIPasteboard.general.image, let cg = ui.normalizedCGImage() else { return }
        pasteImage(cg, at: origin)
    }

    func pasteImage(_ image: CGImage, at origin: CGPoint = .zero) {
        // Grow the canvas if the pasted image is bigger, like Paint does.
        if image.width > canvasWidth || image.height > canvasHeight {
            resizeCanvas(to: CGSize(width: max(canvasWidth, image.width), height: max(canvasHeight, image.height)))
        }
        placeFloating(image: image, at: origin)
    }

    // MARK: - Crop

    func cropToSelection() {
        toolHost?.commitPendingToolWork()
        commitFloating()
        guard let sel = selection else { return }
        let bounds = sel.integralBounds(in: canvasRect)
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        let w = Int(bounds.width), h = Int(bounds.height)
        let isRect = sel.path.isRect(nil)
        let newLayers = layers.map { layer -> RasterLayer in
            let out = layer.transformed(toWidth: w, height: h, transform: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY), interpolate: false)
            if !isRect {
                // Free-form crop: clear everything outside the selection shape.
                var t = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
                if let local = sel.path.copy(using: &t) {
                    let outside = CGMutablePath()
                    outside.addRect(out.bounds)
                    outside.addPath(local)
                    out.context.saveGState()
                    out.context.addPath(outside)
                    out.context.clip(using: .evenOdd)
                    out.context.clear(out.bounds)
                    out.context.restoreGState()
                    out.invalidate()
                }
            }
            return out
        }
        replaceAllLayers(newLayers, size: CGSize(width: w, height: h), label: "Crop")
        fitToWindowRequest += 1
    }
}

extension UIImage {
    /// Returns a CGImage with orientation applied and in a format our layers accept.
    func normalizedCGImage() -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let img = renderer.image { _ in
            draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return img.cgImage
    }
}
