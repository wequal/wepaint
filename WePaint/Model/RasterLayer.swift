import CoreGraphics
import Foundation
import UIKit

/// A rectangular region of layer pixels captured for undo/redo.
struct LayerSnapshot {
    let rect: CGRect // integral, in layer pixel coordinates
    let data: Data
}

/// A raster bitmap layer. Pixels are stored premultiplied RGBA8 in memory order R,G,B,A,
/// row 0 at the top. The CGContext is flipped so that drawing uses top-left coordinates.
final class RasterLayer: Identifiable {
    let id: UUID
    var name: String
    var isVisible: Bool = true
    var opacity: CGFloat = 1

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: UnsafeMutablePointer<UInt8>
    let context: CGContext

    private var cachedImage: CGImage?

    var size: CGSize { CGSize(width: width, height: height) }
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    var byteCount: Int { bytesPerRow * height }

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    init(width: Int, height: Int, name: String, id: UUID = UUID()) {
        let w = max(1, width), h = max(1, height)
        self.id = id
        self.name = name
        self.width = w
        self.height = h
        self.bytesPerRow = w * 4
        self.data = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        self.data.initialize(repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: RasterLayer.colorSpace, bitmapInfo: RasterLayer.bitmapInfo) else {
            fatalError("Unable to create bitmap context")
        }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        self.context = ctx
    }

    deinit {
        data.deallocate()
    }

    // MARK: - Image cache

    func invalidate() {
        cachedImage = nil
    }

    var image: CGImage? {
        if let cachedImage { return cachedImage }
        cachedImage = context.makeImage()
        return cachedImage
    }

    // MARK: - Pixel access

    @inline(__always)
    func pixel(x: Int, y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        let i = (y * width + x) * 4
        return RGBA.fromPremultiplied(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }

    @inline(__always)
    func rawPixel(x: Int, y: Int) -> UInt32 {
        let i = (y * width + x) * 4
        return UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
    }

    @inline(__always)
    func setPixel(x: Int, y: Int, bytes: (UInt8, UInt8, UInt8, UInt8)) {
        let i = (y * width + x) * 4
        data[i] = bytes.0; data[i + 1] = bytes.1; data[i + 2] = bytes.2; data[i + 3] = bytes.3
    }

    // MARK: - Whole-layer operations

    func clear() {
        memset(data, 0, byteCount)
        invalidate()
    }

    func fill(_ color: RGBA) {
        if color.a == 0 { clear(); return }
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor(color.cgColor)
        context.fill(bounds)
        context.restoreGState()
        invalidate()
    }

    func copy(name: String? = nil, id: UUID? = nil) -> RasterLayer {
        let layer = RasterLayer(width: width, height: height, name: name ?? self.name, id: id ?? UUID())
        memcpy(layer.data, data, byteCount)
        layer.isVisible = isVisible
        layer.opacity = opacity
        return layer
    }

    func copyData() -> Data {
        Data(bytes: data, count: byteCount)
    }

    func restore(from fullData: Data) {
        guard fullData.count == byteCount else { return }
        fullData.withUnsafeBytes { src in
            _ = memcpy(data, src.baseAddress!, byteCount)
        }
        invalidate()
    }

    // MARK: - Snapshots

    func integralRect(_ rect: CGRect) -> CGRect {
        rect.integral.intersection(bounds)
    }

    func snapshot(of rect: CGRect) -> LayerSnapshot? {
        let r = integralRect(rect)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return snapshot(integral: r, from: data)
    }

    /// Snapshot of a rect from an arbitrary buffer with this layer's geometry (used for pre-edit backups).
    func snapshot(of rect: CGRect, fromBackup backup: Data) -> LayerSnapshot? {
        let r = integralRect(rect)
        guard !r.isNull, r.width >= 1, r.height >= 1, backup.count == byteCount else { return nil }
        return backup.withUnsafeBytes { raw -> LayerSnapshot in
            let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return snapshot(integral: r, from: UnsafeMutablePointer(mutating: base))
        }
    }

    private func snapshot(integral r: CGRect, from source: UnsafeMutablePointer<UInt8>) -> LayerSnapshot {
        let x0 = Int(r.minX), y0 = Int(r.minY), w = Int(r.width), h = Int(r.height)
        var out = Data(count: w * h * 4)
        out.withUnsafeMutableBytes { dst in
            let d = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for row in 0..<h {
                memcpy(d + row * w * 4, source + ((y0 + row) * width + x0) * 4, w * 4)
            }
        }
        return LayerSnapshot(rect: r, data: out)
    }

    func restore(_ snapshot: LayerSnapshot) {
        let r = snapshot.rect
        let x0 = Int(r.minX), y0 = Int(r.minY), w = Int(r.width), h = Int(r.height)
        guard x0 >= 0, y0 >= 0, x0 + w <= width, y0 + h <= height, snapshot.data.count == w * h * 4 else { return }
        snapshot.data.withUnsafeBytes { src in
            let s = src.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for row in 0..<h {
                memcpy(data + ((y0 + row) * width + x0) * 4, s + row * w * 4, w * 4)
            }
        }
        invalidate()
    }

    // MARK: - Drawing helpers

    /// Draws a CGImage upright (compensating for the flipped context).
    func draw(_ image: CGImage, in rect: CGRect, alpha: CGFloat = 1, blendMode: CGBlendMode = .normal, interpolate: Bool = true) {
        context.saveGState()
        context.setAlpha(alpha)
        context.setBlendMode(blendMode)
        context.interpolationQuality = interpolate ? .high : .none
        context.drawUpright(image, in: rect)
        context.restoreGState()
        invalidate()
    }

    /// Returns a new layer of a different size with this layer's content drawn into it using `transform`
    /// (expressed in top-left pixel coordinates).
    func transformed(toWidth w: Int, height h: Int, transform: CGAffineTransform, interpolate: Bool = true) -> RasterLayer {
        let out = RasterLayer(width: w, height: h, name: name, id: id)
        out.isVisible = isVisible
        out.opacity = opacity
        if let img = image {
            out.context.saveGState()
            out.context.concatenate(transform)
            out.context.interpolationQuality = interpolate ? .high : .none
            out.context.drawUpright(img, in: bounds)
            out.context.restoreGState()
            out.invalidate()
        }
        return out
    }

    /// Returns a CGImage of the given integral rect.
    func cropped(to rect: CGRect) -> CGImage? {
        image?.cropping(to: integralRect(rect))
    }
}

extension CGContext {
    /// Draws an image so that it appears upright in a context whose origin is top-left (flipped).
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }
}
