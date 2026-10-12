import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Hooks that let the document ask the live canvas to finish or discard in-progress tool work.
protocol ToolHost: AnyObject {
    /// Finish any pending tool work (e.g. an uncommitted shape or text) so it is baked into pixels.
    func commitPendingToolWork()
    /// Discard pending tool work without applying it.
    func cancelPendingToolWork()
}

struct TextEditingState: Equatable {
    var origin: CGPoint
    var size: CGSize
    var text: String = ""
}

@Observable
final class PaintDocument {
    static let defaultSize = CGSize(width: 1152, height: 648)

    // MARK: Canvas & layers

    private(set) var canvasWidth: Int
    private(set) var canvasHeight: Int
    /// Bottom-most layer first.
    private(set) var layers: [RasterLayer]
    var activeLayerID: UUID
    private(set) var backgroundLayerID: UUID
    /// When true the background layer is transparent instead of filled with the secondary color.
    var transparentBackground = false

    var canvasSize: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }
    var canvasRect: CGRect { CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight) }

    var activeLayer: RasterLayer {
        layers.first(where: { $0.id == activeLayerID }) ?? layers[0]
    }

    var activeLayerIsBackground: Bool { activeLayerID == backgroundLayerID }

    // MARK: Colors

    var primaryColor: RGBA = .black
    var secondaryColor: RGBA = .white
    var colorTarget: ColorTarget = .primary
    var customColors: [RGBA] = []

    // MARK: Tool settings

    var activeTool: ToolKind = .pencil {
        willSet { if newValue != activeTool { toolHost?.commitPendingToolWork() } }
        didSet { if oldValue != activeTool { previousTool = oldValue; cursorPosition = nil } }
    }
    private(set) var previousTool: ToolKind = .pencil
    var brushKind: BrushKind = .brush
    var shapeKind: ShapeKind = .rectangle
    var shapeOutline: ShapeOutlineStyle = .solid
    var shapeFill: ShapeFillStyle = .none
    var selectMode: SelectMode = .rectangle
    var transparentSelection = false
    var strokeWidth: CGFloat = 4
    var fillTolerance: Int = 0
    var textStyle = TextStyle()

    // MARK: Selection

    var selection: Selection?
    var floating: FloatingSelection?
    var textEditing: TextEditingState?
    var hasSelection: Bool { selection != nil || floating != nil }

    // MARK: View state

    var zoom: CGFloat = 1
    /// A one-shot request to zoom to `zoom` centred on this canvas point.
    var zoomFocus: CGPoint?
    var fitToWindowRequest = 0
    var cursorPosition: CGPoint?
    var showGrid = false
    var showLayersPanel = true
    var showStatusBar = true

    // MARK: History & dirty state

    let history = HistoryManager()
    private(set) var renderVersion = 0
    var isDirty = false
    var fileName = "Untitled"

    @ObservationIgnored weak var toolHost: ToolHost?
    @ObservationIgnored var onInvalidate: ((CGRect?) -> Void)?
    @ObservationIgnored private var editBackup: Data?
    @ObservationIgnored private var editLayer: RasterLayer?

    // MARK: - Init

    init(size: CGSize = PaintDocument.defaultSize) {
        let w = Int(size.width), h = Int(size.height)
        canvasWidth = w
        canvasHeight = h
        let bg = RasterLayer(width: w, height: h, name: "Background")
        bg.fill(.white)
        layers = [bg]
        activeLayerID = bg.id
        backgroundLayerID = bg.id
    }

    // MARK: - Rendering notifications

    func invalidate(_ rect: CGRect? = nil) {
        onInvalidate?(rect)
    }

    func bumpRender() {
        renderVersion &+= 1
        onInvalidate?(nil)
    }

    private func markChanged() {
        isDirty = true
        bumpRender()
    }

    // MARK: - Pixel edits with undo

    /// Begin a pixel edit on `layer`. A full copy of the layer is kept until `endPixelEdit`.
    func beginPixelEdit(on layer: RasterLayer? = nil) {
        let target = layer ?? activeLayer
        editLayer = target
        editBackup = target.copyData()
    }

    /// Finish a pixel edit, recording before/after snapshots of `dirtyRect` for undo.
    func endPixelEdit(label: String, dirtyRect: CGRect) {
        defer { editBackup = nil; editLayer = nil }
        guard let layer = editLayer, let backup = editBackup else { return }
        layer.invalidate()
        let rect = dirtyRect.insetBy(dx: -2, dy: -2)
        guard let before = layer.snapshot(of: rect, fromBackup: backup),
              let after = layer.snapshot(of: rect) else {
            bumpRender()
            return
        }
        if before.data == after.data {
            bumpRender()
            return
        }
        history.push(label: label,
                     undo: { [weak self] in layer.restore(before); self?.markChanged() },
                     redo: { [weak self] in layer.restore(after); self?.markChanged() })
        markChanged()
    }

    func cancelPixelEdit() {
        if let layer = editLayer, let backup = editBackup {
            layer.restore(from: backup)
            bumpRender()
        }
        editBackup = nil
        editLayer = nil
    }

    /// Runs a whole-layer edit with full undo.
    func performLayerEdit(label: String, on layer: RasterLayer? = nil, _ body: (RasterLayer) -> Void) {
        let target = layer ?? activeLayer
        beginPixelEdit(on: target)
        body(target)
        endPixelEdit(label: label, dirtyRect: target.bounds)
    }

    // MARK: - Undo / redo

    func undo() {
        toolHost?.cancelPendingToolWork()
        commitFloating()
        history.undo()
        clampActiveLayer()
        markChanged()
    }

    func redo() {
        toolHost?.cancelPendingToolWork()
        commitFloating()
        history.redo()
        clampActiveLayer()
        markChanged()
    }

    private func clampActiveLayer() {
        if !layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = layers.last!.id
        }
    }

    // MARK: - Layer management

    func layerIndex(of id: UUID) -> Int? {
        layers.firstIndex(where: { $0.id == id })
    }

    func setLayers(_ newLayers: [RasterLayer], label: String) {
        let old = layers
        let oldActive = activeLayerID
        layers = newLayers
        clampActiveLayer()
        let newActive = activeLayerID
        history.push(label: label,
                     undo: { [weak self] in self?.layers = old; self?.activeLayerID = oldActive; self?.markChanged() },
                     redo: { [weak self] in self?.layers = newLayers; self?.activeLayerID = newActive; self?.markChanged() })
        markChanged()
    }

    func addLayer() {
        toolHost?.commitPendingToolWork()
        commitFloating()
        let layer = RasterLayer(width: canvasWidth, height: canvasHeight, name: "Layer \(layers.count + 1)")
        var new = layers
        let idx = (layerIndex(of: activeLayerID) ?? layers.count - 1) + 1
        new.insert(layer, at: idx)
        setLayers(new, label: "Add layer")
        activeLayerID = layer.id
    }

    func duplicateLayer(_ id: UUID? = nil) {
        toolHost?.commitPendingToolWork()
        commitFloating()
        let target = id ?? activeLayerID
        guard let idx = layerIndex(of: target) else { return }
        let copy = layers[idx].copy(name: layers[idx].name + " copy")
        var new = layers
        new.insert(copy, at: idx + 1)
        setLayers(new, label: "Duplicate layer")
        activeLayerID = copy.id
    }

    func deleteLayer(_ id: UUID? = nil) {
        toolHost?.commitPendingToolWork()
        commitFloating()
        let target = id ?? activeLayerID
        guard layers.count > 1, let idx = layerIndex(of: target) else { return }
        var new = layers
        new.remove(at: idx)
        if target == backgroundLayerID { backgroundLayerID = new[0].id }
        setLayers(new, label: "Delete layer")
        activeLayerID = new[min(idx, new.count - 1)].id
    }

    func mergeDown(_ id: UUID? = nil) {
        toolHost?.commitPendingToolWork()
        commitFloating()
        let target = id ?? activeLayerID
        guard let idx = layerIndex(of: target), idx > 0 else { return }
        let top = layers[idx]
        let bottom = layers[idx - 1]
        let merged = bottom.copy(name: bottom.name, id: bottom.id)
        if top.isVisible, let img = top.image {
            merged.draw(img, in: merged.bounds, alpha: top.opacity)
        }
        var new = layers
        new.remove(at: idx)
        new[idx - 1] = merged
        setLayers(new, label: "Merge down")
        activeLayerID = merged.id
    }

    func moveLayer(from source: Int, to destination: Int) {
        guard source != destination, layers.indices.contains(source), (0...layers.count).contains(destination) else { return }
        var new = layers
        let item = new.remove(at: source)
        new.insert(item, at: destination > source ? destination - 1 : destination)
        setLayers(new, label: "Reorder layers")
    }

    func moveLayerUp(_ id: UUID) {
        guard let idx = layerIndex(of: id), idx < layers.count - 1 else { return }
        var new = layers
        new.swapAt(idx, idx + 1)
        setLayers(new, label: "Move layer up")
    }

    func moveLayerDown(_ id: UUID) {
        guard let idx = layerIndex(of: id), idx > 0 else { return }
        var new = layers
        new.swapAt(idx, idx - 1)
        setLayers(new, label: "Move layer down")
    }

    func setLayerVisible(_ id: UUID, _ visible: Bool) {
        guard let layer = layers.first(where: { $0.id == id }), layer.isVisible != visible else { return }
        let old = layer.isVisible
        layer.isVisible = visible
        history.push(label: visible ? "Show layer" : "Hide layer",
                     undo: { [weak self] in layer.isVisible = old; self?.markChanged() },
                     redo: { [weak self] in layer.isVisible = visible; self?.markChanged() })
        markChanged()
    }

    func setLayerOpacity(_ id: UUID, _ opacity: CGFloat, recordUndo: Bool = true) {
        guard let layer = layers.first(where: { $0.id == id }) else { return }
        let old = layer.opacity
        layer.opacity = opacity
        if recordUndo, abs(old - opacity) > 0.001 {
            history.push(label: "Layer opacity",
                         undo: { [weak self] in layer.opacity = old; self?.markChanged() },
                         redo: { [weak self] in layer.opacity = opacity; self?.markChanged() })
        }
        markChanged()
    }

    func renameLayer(_ id: UUID, _ name: String) {
        guard let layer = layers.first(where: { $0.id == id }), layer.name != name else { return }
        let old = layer.name
        layer.name = name
        history.push(label: "Rename layer",
                     undo: { [weak self] in layer.name = old; self?.bumpRender() },
                     redo: { [weak self] in layer.name = name; self?.bumpRender() })
        bumpRender()
    }

    func selectLayer(_ id: UUID) {
        guard id != activeLayerID else { return }
        toolHost?.commitPendingToolWork()
        commitFloating()
        activeLayerID = id
    }

    /// Replaces every layer and the canvas size (used by image transforms, crop, open).
    func replaceAllLayers(_ newLayers: [RasterLayer], size: CGSize, label: String, resetHistory: Bool = false) {
        let old = layers
        let oldSize = canvasSize
        let oldActive = activeLayerID
        let oldBackground = backgroundLayerID
        let newBackground = newLayers.first(where: { $0.id == oldBackground })?.id ?? newLayers[0].id
        let apply: (([RasterLayer], CGSize, UUID, UUID) -> Void) = { [weak self] ls, s, active, bg in
            guard let self else { return }
            self.layers = ls
            self.canvasWidth = Int(s.width)
            self.canvasHeight = Int(s.height)
            self.backgroundLayerID = bg
            self.activeLayerID = ls.contains(where: { $0.id == active }) ? active : ls[0].id
            self.selection = nil
            self.floating = nil
            self.markChanged()
        }
        apply(newLayers, size, oldActive, newBackground)
        if resetHistory {
            history.clear()
        } else {
            history.push(label: label,
                         undo: { apply(old, oldSize, oldActive, oldBackground) },
                         redo: { apply(newLayers, size, oldActive, newBackground) })
        }
    }

    // MARK: - Compositing

    /// Flattens all visible layers. If `background` is non-nil the result is composited over that color.
    func flattenedImage(background: RGBA? = nil, includeFloating: Bool = true) -> CGImage? {
        let w = canvasWidth, h = canvasHeight
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: RasterLayer.colorSpace, bitmapInfo: RasterLayer.bitmapInfo) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(canvasRect)
        }
        for layer in layers where layer.isVisible {
            if let img = layer.image {
                ctx.setAlpha(layer.opacity)
                ctx.drawUpright(img, in: canvasRect)
            }
            if includeFloating, layer.id == activeLayerID, let f = floating {
                ctx.setAlpha(layer.opacity)
                ctx.drawUpright(f.image, in: f.frame)
            }
        }
        return ctx.makeImage()
    }

    /// Composite color under a canvas point (used by the color picker).
    func compositeColor(at p: CGPoint) -> RGBA? {
        let x = Int(p.x), y = Int(p.y)
        guard canvasRect.contains(CGPoint(x: x, y: y)) else { return nil }
        guard let img = flattenedImage(includeFloating: true),
              let crop = img.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: RasterLayer.colorSpace, bitmapInfo: RasterLayer.bitmapInfo) else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return RGBA.fromPremultiplied(r: px[0], g: px[1], b: px[2], a: px[3])
    }

    // MARK: - Documents

    func newDocument(size: CGSize) {
        toolHost?.cancelPendingToolWork()
        let w = Int(size.width), h = Int(size.height)
        let bg = RasterLayer(width: w, height: h, name: "Background")
        bg.fill(transparentBackground ? .clear : secondaryColor)
        canvasWidth = w
        canvasHeight = h
        layers = [bg]
        activeLayerID = bg.id
        backgroundLayerID = bg.id
        selection = nil
        floating = nil
        textEditing = nil
        history.clear()
        isDirty = false
        fileName = "Untitled"
        fitToWindowRequest += 1
        bumpRender()
    }

    func load(image: CGImage, name: String) {
        toolHost?.cancelPendingToolWork()
        let w = image.width, h = image.height
        let bg = RasterLayer(width: w, height: h, name: "Background")
        bg.draw(image, in: bg.bounds)
        canvasWidth = w
        canvasHeight = h
        layers = [bg]
        activeLayerID = bg.id
        backgroundLayerID = bg.id
        selection = nil
        floating = nil
        textEditing = nil
        history.clear()
        isDirty = false
        fileName = name
        fitToWindowRequest += 1
        bumpRender()
    }

    // MARK: - Colors

    func applyColor(_ color: RGBA) {
        switch colorTarget {
        case .primary: primaryColor = color
        case .secondary: secondaryColor = color
        }
    }

    func addCustomColor(_ color: RGBA) {
        customColors.removeAll { $0 == color }
        customColors.insert(color, at: 0)
        if customColors.count > 10 { customColors.removeLast(customColors.count - 10) }
    }

    func swapColors() {
        swap(&primaryColor, &secondaryColor)
    }

    /// The color the eraser paints with on the current layer (nil = erase to transparent).
    var eraseColor: RGBA? {
        activeLayerIsBackground && !transparentBackground ? secondaryColor : nil
    }

    // MARK: - Zoom helpers

    func zoomIn(at point: CGPoint? = nil) {
        zoom = ZoomLevels.next(after: zoom)
        zoomFocus = point
    }

    func zoomOut(at point: CGPoint? = nil) {
        zoom = ZoomLevels.previous(before: zoom)
        zoomFocus = point
    }

    func setZoom(_ z: CGFloat) {
        zoom = min(ZoomLevels.maximum, max(ZoomLevels.minimum, z))
        zoomFocus = nil
    }

    func fitToWindow() {
        fitToWindowRequest += 1
    }

    /// Restores the previously selected tool (used after picking a color).
    func restorePreviousTool() {
        activeTool = previousTool
    }
}
