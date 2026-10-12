import CoreGraphics
import UIKit

// MARK: - Fill with color (flood fill)

final class FillTool: Tool {
    var kind: ToolKind { .fill }
    private var start: CGPoint = .zero

    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        start = touch.location
    }

    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext) {}

    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext) {
        let doc = ctx.document
        doc.commitFloating()
        let p = touch.location
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < doc.canvasWidth, y < doc.canvasHeight else { return }
        if let sel = doc.selection, !sel.contains(p) { return }
        let layer = ctx.layer
        doc.beginPixelEdit(on: layer)
        let rect = FloodFill.fill(layer: layer, x: x, y: y, color: doc.primaryColor,
                                  tolerance: doc.fillTolerance, restrictTo: doc.selection)
        if let rect {
            doc.endPixelEdit(label: "Fill", dirtyRect: rect)
        } else {
            doc.cancelPixelEdit()
        }
    }

    func touchCancelled(_ ctx: ToolContext) {}
}

enum FloodFill {
    /// Scanline flood fill. Returns the dirty rect, or nil if nothing changed.
    static func fill(layer: RasterLayer, x sx: Int, y sy: Int, color: RGBA, tolerance: Int, restrictTo selection: Selection?) -> CGRect? {
        let w = layer.width, h = layer.height
        let data = layer.data
        let target = layer.rawPixel(x: sx, y: sy)
        let fillBytes = color.premultipliedBytes
        let fillRaw = UInt32(fillBytes.0) << 24 | UInt32(fillBytes.1) << 16 | UInt32(fillBytes.2) << 8 | UInt32(fillBytes.3)
        if tolerance == 0, target == fillRaw { return nil }

        // Tolerance 0...100 maps to a maximum per-channel-ish squared distance.
        let maxDist: Int = {
            let t = max(0, min(100, tolerance))
            let perChannel = Int(Double(t) / 100.0 * 255.0)
            return perChannel * perChannel * 4
        }()
        let tr = Int((target >> 24) & 0xFF), tg = Int((target >> 16) & 0xFF), tb = Int((target >> 8) & 0xFF), ta = Int(target & 0xFF)

        var mask: [Bool]? = nil
        if let selection, let m = selection.maskImage(size: layer.size), let provider = m.dataProvider, let cf = provider.data {
            let bytes = CFDataGetBytePtr(cf)!
            let bpr = m.bytesPerRow
            var arr = [Bool](repeating: false, count: w * h)
            for yy in 0..<h {
                for xx in 0..<w {
                    arr[yy * w + xx] = bytes[yy * bpr + xx] > 127
                }
            }
            mask = arr
        }

        @inline(__always) func matches(_ x: Int, _ y: Int, _ visited: UnsafeMutablePointer<Bool>) -> Bool {
            let idx = y * w + x
            if visited[idx] { return false }
            if let mask, !mask[idx] { return false }
            let p = idx * 4
            if maxDist == 0 {
                return data[p] == UInt8(tr) && data[p + 1] == UInt8(tg) && data[p + 2] == UInt8(tb) && data[p + 3] == UInt8(ta)
            }
            let dr = Int(data[p]) - tr, dg = Int(data[p + 1]) - tg, db = Int(data[p + 2]) - tb, da = Int(data[p + 3]) - ta
            return dr * dr + dg * dg + db * db + da * da <= maxDist
        }

        let visited = UnsafeMutablePointer<Bool>.allocate(capacity: w * h)
        visited.initialize(repeating: false, count: w * h)
        defer { visited.deallocate() }

        var minX = sx, maxX = sx, minY = sy, maxY = sy
        var stack: [(Int, Int)] = [(sx, sy)]
        stack.reserveCapacity(1024)
        var changed = false

        while let (x0, y) = stack.popLast() {
            guard matches(x0, y, visited) else { continue }
            var left = x0, right = x0
            while left - 1 >= 0, matches(left - 1, y, visited) { left -= 1 }
            while right + 1 < w, matches(right + 1, y, visited) { right += 1 }
            for x in left...right {
                let idx = y * w + x
                visited[idx] = true
                let p = idx * 4
                data[p] = fillBytes.0; data[p + 1] = fillBytes.1; data[p + 2] = fillBytes.2; data[p + 3] = fillBytes.3
            }
            changed = true
            minX = min(minX, left); maxX = max(maxX, right); minY = min(minY, y); maxY = max(maxY, y)
            for ny in [y - 1, y + 1] where ny >= 0 && ny < h {
                var x = left
                while x <= right {
                    if matches(x, ny, visited) {
                        stack.append((x, ny))
                        // Skip the rest of this run; it will be filled when popped.
                        while x <= right, matches(x, ny, visited) { x += 1 }
                    } else {
                        x += 1
                    }
                }
            }
        }
        layer.invalidate()
        guard changed else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

// MARK: - Color picker (eyedropper)

final class ColorPickerTool: Tool {
    var kind: ToolKind { .colorPicker }
    private(set) var previewColor: RGBA?
    private var previewPoint: CGPoint?

    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        update(touch, ctx)
    }

    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext) {
        update(touch, ctx)
    }

    private func update(_ touch: ToolTouch, _ ctx: ToolContext) {
        previewPoint = touch.location
        previewColor = ctx.layer.pixel(x: Int(touch.location.x), y: Int(touch.location.y))
        ctx.invalidateOverlay()
    }

    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext) {
        let doc = ctx.document
        previewPoint = nil
        previewColor = nil
        ctx.invalidateOverlay()
        guard let c = doc.compositeColor(at: touch.location) else { return }
        doc.applyColor(c.a == 0 ? .white : RGBA(r: c.r, g: c.g, b: c.b))
        doc.restorePreviousTool()
    }

    func touchCancelled(_ ctx: ToolContext) {
        previewPoint = nil
        previewColor = nil
        ctx.invalidateOverlay()
    }

    func drawOverlay(_ cg: CGContext, _ ctx: ToolContext) {
        guard let p = previewPoint, let c = previewColor else { return }
        let z = ctx.zoom
        let r: CGFloat = 18 / z
        let rect = CGRect(x: p.x - r, y: p.y - r * 3, width: r * 2, height: r * 2)
        cg.saveGState()
        cg.setFillColor(c.uiColor.cgColor)
        cg.fillEllipse(in: rect)
        cg.setLineWidth(2 / z)
        cg.setStrokeColor(UIColor.white.cgColor)
        cg.strokeEllipse(in: rect)
        cg.setLineWidth(1 / z)
        cg.setStrokeColor(UIColor.black.cgColor)
        cg.strokeEllipse(in: rect.insetBy(dx: -1.5 / z, dy: -1.5 / z))
        cg.restoreGState()
    }
}

// MARK: - Magnifier

final class MagnifierTool: Tool {
    var kind: ToolKind { .magnifier }
    private var start: CGPoint = .zero

    func touchBegan(_ touch: ToolTouch, _ ctx: ToolContext) {
        start = touch.location
    }

    func touchMoved(_ touch: ToolTouch, _ ctx: ToolContext) {}

    func touchEnded(_ touch: ToolTouch, _ ctx: ToolContext) {
        guard start.distance(to: touch.location) < 12 / ctx.zoom else { return }
        ctx.document.zoomIn(at: touch.location)
    }

    func touchCancelled(_ ctx: ToolContext) {}
}
