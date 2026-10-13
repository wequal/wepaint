import CoreGraphics
import Foundation

enum RotationAmount {
    case clockwise90, counterClockwise90, half

    var title: String {
        switch self {
        case .clockwise90: return "Rotate right 90°"
        case .counterClockwise90: return "Rotate left 90°"
        case .half: return "Rotate 180°"
        }
    }
}

enum FlipDirection {
    case horizontal, vertical
}

extension PaintDocument {
    /// Applies an affine transform (top-left pixel coordinates) to every layer, producing a canvas of `size`.
    private func transformAllLayers(to size: CGSize, transform: CGAffineTransform, label: String, interpolate: Bool = true,
                                    fillBackground: Bool = false) {
        toolHost?.commitPendingToolWork()
        commitFloating()
        let w = max(1, Int(size.width.rounded())), h = max(1, Int(size.height.rounded()))
        let sizeChanged = w != canvasWidth || h != canvasHeight
        let newLayers = layers.map { layer -> RasterLayer in
            if fillBackground, layer.id == backgroundLayerID, !transparentBackground {
                let out = RasterLayer(width: w, height: h, name: layer.name, id: layer.id)
                out.isVisible = layer.isVisible
                out.opacity = layer.opacity
                out.fill(secondaryColor)
                if let img = layer.image {
                    out.context.saveGState()
                    out.context.concatenate(transform)
                    out.context.interpolationQuality = interpolate ? .high : .none
                    out.context.drawUpright(img, in: layer.bounds)
                    out.context.restoreGState()
                    out.invalidate()
                }
                return out
            }
            return layer.transformed(toWidth: w, height: h, transform: transform, interpolate: interpolate)
        }
        replaceAllLayers(newLayers, size: CGSize(width: w, height: h), label: label)
        if sizeChanged { fitToWindowRequest += 1 }
    }

    /// Rotates the selection if there is one, otherwise the whole image.
    func rotate(_ amount: RotationAmount) {
        if hasSelection { rotateSelection(amount); return }
        let w = CGFloat(canvasWidth), h = CGFloat(canvasHeight)
        switch amount {
        case .clockwise90:
            transformAllLayers(to: CGSize(width: h, height: w),
                               transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0),
                               label: amount.title, interpolate: false)
        case .counterClockwise90:
            transformAllLayers(to: CGSize(width: h, height: w),
                               transform: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w),
                               label: amount.title, interpolate: false)
        case .half:
            transformAllLayers(to: canvasSize,
                               transform: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h),
                               label: amount.title, interpolate: false)
        }
        fitToWindowRequest += 1
    }

    /// Flips the selection if there is one, otherwise the whole image.
    func flip(_ direction: FlipDirection) {
        if hasSelection { flipSelection(direction); return }
        let w = CGFloat(canvasWidth), h = CGFloat(canvasHeight)
        switch direction {
        case .horizontal:
            transformAllLayers(to: canvasSize, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0),
                               label: "Flip horizontal", interpolate: false)
        case .vertical:
            transformAllLayers(to: canvasSize, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h),
                               label: "Flip vertical", interpolate: false)
        }
    }

    /// Resizes the selection (if any) or the image by independent horizontal/vertical scale factors.
    func resizeImage(scaleX: CGFloat, scaleY: CGFloat) {
        guard scaleX > 0, scaleY > 0 else { return }
        if hasSelection { resizeSelection(scaleX: scaleX, scaleY: scaleY); return }
        let newW = max(1, (CGFloat(canvasWidth) * scaleX).rounded())
        let newH = max(1, (CGFloat(canvasHeight) * scaleY).rounded())
        resizeImage(toPixelWidth: Int(newW), height: Int(newH))
    }

    /// Resizes the selection (if any) or the image to the given pixel size.
    func resizeImage(toPixelWidth newW: Int, height newH: Int) {
        guard newW >= 1, newH >= 1, newW <= 8192, newH <= 8192 else { return }
        if hasSelection { resizeSelection(toPixelWidth: newW, height: newH); return }
        let sx = CGFloat(newW) / CGFloat(canvasWidth)
        let sy = CGFloat(newH) / CGFloat(canvasHeight)
        transformAllLayers(to: CGSize(width: newW, height: newH), transform: CGAffineTransform(scaleX: sx, y: sy), label: "Resize")
    }

    /// Skews the selection (if any) or the image by the given angles in degrees (as in Paint's Resize and Skew dialog).
    func skewImage(horizontalDegrees: CGFloat, verticalDegrees: CGFloat) {
        if hasSelection { skewSelection(horizontalDegrees: horizontalDegrees, verticalDegrees: verticalDegrees); return }
        let hd = max(-89, min(89, horizontalDegrees)), vd = max(-89, min(89, verticalDegrees))
        guard abs(hd) > 0.01 || abs(vd) > 0.01 else { return }
        let th = tan(hd * .pi / 180), tv = tan(vd * .pi / 180)
        // x' = x + th*y ; y' = y + tv*x
        var t = CGAffineTransform(a: 1, b: tv, c: th, d: 1, tx: 0, ty: 0)
        let box = canvasRect.applying(t)
        t = t.concatenating(CGAffineTransform(translationX: -box.minX, y: -box.minY))
        transformAllLayers(to: CGSize(width: box.width.rounded(.up), height: box.height.rounded(.up)), transform: t, label: "Skew")
    }

    /// Changes the canvas size, anchoring existing content at the top-left.
    func resizeCanvas(to size: CGSize) {
        let w = max(1, Int(size.width)), h = max(1, Int(size.height))
        guard w != canvasWidth || h != canvasHeight, w <= 8192, h <= 8192 else { return }
        transformAllLayers(to: CGSize(width: w, height: h), transform: .identity, label: "Resize canvas",
                           interpolate: false, fillBackground: true)
    }

    /// Toggles a transparent background: fills or clears the background layer accordingly.
    func setTransparentBackground(_ transparent: Bool) {
        guard transparent != transparentBackground else { return }
        toolHost?.commitPendingToolWork()
        commitFloating()
        let old = transparentBackground
        transparentBackground = transparent
        guard let bg = layers.first(where: { $0.id == backgroundLayerID }) else { return }
        beginPixelEdit(on: bg)
        if transparent {
            // Make pixels matching the secondary color transparent.
            let key = secondaryColor.premultipliedBytes
            let n = bg.width * bg.height
            for i in 0..<n {
                let p = i * 4
                if bg.data[p] == key.0, bg.data[p + 1] == key.1, bg.data[p + 2] == key.2, bg.data[p + 3] == key.3 {
                    bg.data[p] = 0; bg.data[p + 1] = 0; bg.data[p + 2] = 0; bg.data[p + 3] = 0
                }
            }
            bg.invalidate()
        } else {
            // Composite over the secondary color.
            if let img = bg.image {
                bg.fill(secondaryColor)
                bg.draw(img, in: bg.bounds)
            }
        }
        endPixelEdit(label: transparent ? "Transparent background" : "Opaque background", dirtyRect: bg.bounds)
        // Make the transparency flag itself undoable alongside the pixels.
        history.push(label: "Background transparency",
                     undo: { [weak self] in self?.transparentBackground = old },
                     redo: { [weak self] in self?.transparentBackground = transparent })
    }

    /// Converts the whole image to grayscale (Paint's "Black and white" image property).
    func convertToGrayscale() {
        toolHost?.commitPendingToolWork()
        commitFloating()
        for layer in layers {
            performLayerEdit(label: "Black and white", on: layer) { l in
                let n = l.width * l.height
                for i in 0..<n {
                    let p = i * 4
                    let r = Int(l.data[p]), g = Int(l.data[p + 1]), b = Int(l.data[p + 2])
                    let y = UInt8((r * 299 + g * 587 + b * 114) / 1000)
                    l.data[p] = y; l.data[p + 1] = y; l.data[p + 2] = y
                }
                l.invalidate()
            }
        }
    }
}
