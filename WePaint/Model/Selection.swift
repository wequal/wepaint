import CoreGraphics
import UIKit

/// A fixed selection region on the canvas (not yet lifted from the pixels).
struct Selection {
    /// Path in canvas pixel coordinates, filled with the even-odd rule.
    var path: CGPath

    static func rect(_ r: CGRect) -> Selection {
        Selection(path: CGPath(rect: r.standardized, transform: nil))
    }

    var bounds: CGRect { path.boundingBoxOfPath }

    func integralBounds(in canvas: CGRect) -> CGRect {
        bounds.integral.intersection(canvas)
    }

    func contains(_ p: CGPoint) -> Bool {
        path.contains(p, using: .evenOdd)
    }

    /// Builds an alpha mask image for the given canvas size (255 inside selection).
    func maskImage(size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
        return ctx.makeImage()
    }

    /// Inverts the selection relative to the canvas.
    func inverted(in canvas: CGRect) -> Selection {
        let p = CGMutablePath()
        p.addRect(canvas)
        p.addPath(path)
        return Selection(path: p)
    }

    func translated(by d: CGSize) -> Selection {
        var t = CGAffineTransform(translationX: d.width, y: d.height)
        return Selection(path: path.copy(using: &t) ?? path)
    }
}

/// Pixels that were lifted off a layer and can be moved/resized before being committed.
struct FloatingSelection {
    /// The lifted pixels (already masked to the selection shape, transparent outside).
    var image: CGImage
    /// Where the pixels are placed on the canvas. May differ in size from `image` when scaled.
    var frame: CGRect
    /// Selection outline in local coordinates relative to the original lifted bounds.
    var localPath: CGPath
    /// Where the pixels were lifted from (used to scale the outline when resizing and for undo bounds).
    var originalFrame: CGRect
    var originalSize: CGSize { originalFrame.size }

    /// The outline in canvas coordinates.
    var canvasPath: CGPath {
        let sx = originalSize.width > 0 ? frame.width / originalSize.width : 1
        let sy = originalSize.height > 0 ? frame.height / originalSize.height : 1
        var t = CGAffineTransform(translationX: frame.minX, y: frame.minY).scaledBy(x: sx, y: sy)
        return localPath.copy(using: &t) ?? localPath
    }

    func contains(_ p: CGPoint) -> Bool {
        frame.contains(p)
    }
}
