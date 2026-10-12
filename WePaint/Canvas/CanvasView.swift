import UIKit

/// Renders the document's layers at 1 point per pixel and routes single-touch input to the active tool.
/// It lives inside a UIScrollView which provides zooming and (two-finger) panning.
final class CanvasView: UIView, ToolHost {
    let document: PaintDocument
    private(set) var tools: [ToolKind: Tool] = [:]
    private(set) lazy var toolContext = ToolContext(document: document, canvas: self)
    weak var overlay: OverlayView?
    private(set) var textBox: TextBoxView?

    private var activeTouch: UITouch?
    /// When true, single finger touches scroll instead of draw (Apple Pencil still draws).
    var fingerPans = false

    private static let checkerImage: UIImage = {
        let size = 16
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { c in
            UIColor(white: 0.93, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor(white: 0.78, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: size / 2, height: size / 2))
            c.fill(CGRect(x: size / 2, y: size / 2, width: size / 2, height: size / 2))
        }
    }()

    init(document: PaintDocument) {
        self.document = document
        super.init(frame: CGRect(origin: .zero, size: document.canvasSize))
        isMultipleTouchEnabled = false
        isOpaque = true
        backgroundColor = .white
        contentMode = .redraw
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .linear
        document.toolHost = self
        document.onInvalidate = { [weak self] rect in self?.invalidateCanvas(rect) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var activeTool: Tool {
        let kind = document.activeTool
        if let t = tools[kind] { return t }
        let t: Tool
        switch kind {
        case .select: t = SelectTool()
        case .pencil: t = PencilTool()
        case .fill: t = FillTool()
        case .text: t = TextTool()
        case .eraser: t = EraserTool()
        case .colorPicker: t = ColorPickerTool()
        case .magnifier: t = MagnifierTool()
        case .brush: t = BrushTool()
        case .shape: t = ShapeTool()
        }
        tools[kind] = t
        return t
    }

    // MARK: - ToolHost

    func commitPendingToolWork() {
        for tool in tools.values { tool.commitPending(toolContext) }
        if document.textEditing != nil { (tools[.text] as? TextTool)?.commitPending(toolContext) }
    }

    func cancelPendingToolWork() {
        for tool in tools.values { tool.cancelPending(toolContext) }
        if let t = activeTouch {
            activeTouch = nil
            _ = t
            activeTool.touchCancelled(toolContext)
        }
    }

    // MARK: - Invalidation

    func invalidateCanvas(_ rect: CGRect?) {
        if let rect {
            setNeedsDisplay(rect.integral.insetBy(dx: -1, dy: -1))
        } else {
            setNeedsDisplay()
        }
        overlay?.setNeedsDisplay()
    }

    func invalidateOverlay() {
        overlay?.setNeedsDisplay()
    }

    /// Called when the document's canvas size changes.
    func syncSize() {
        let size = document.canvasSize
        if bounds.size != size {
            let t = transform
            transform = .identity
            frame = CGRect(origin: .zero, size: size)
            transform = t
            center = CGPoint(x: frame.width / 2, y: frame.height / 2)
            toolContext.ensureScratchSize()
            setNeedsDisplay()
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let canvasRect = document.canvasRect
        cg.interpolationQuality = .none
        cg.setShouldAntialias(false)

        // Checkerboard for transparency.
        cg.saveGState()
        cg.clip(to: rect)
        Self.checkerImage.drawAsPattern(in: canvasRect)
        cg.restoreGState()

        for layer in document.layers where layer.isVisible {
            if let img = layer.image {
                cg.saveGState()
                cg.setAlpha(layer.opacity)
                cg.drawUpright(img, in: canvasRect)
                cg.restoreGState()
            }
            if layer.id == document.activeLayerID {
                if toolContext.scratchVisible, let s = toolContext.scratch.image {
                    cg.saveGState()
                    cg.setAlpha(toolContext.scratchAlpha * layer.opacity)
                    cg.setBlendMode(toolContext.scratchBlendMode)
                    cg.drawUpright(s, in: canvasRect)
                    cg.restoreGState()
                }
                if let f = document.floating {
                    cg.saveGState()
                    cg.setAlpha(layer.opacity)
                    cg.interpolationQuality = .high
                    cg.drawUpright(f.image, in: f.frame)
                    cg.restoreGState()
                }
            }
        }
    }

    /// Draws overlay content in canvas coordinates (called by OverlayView with a transformed context).
    func drawOverlayContent(_ cg: CGContext) {
        let z = max(0.01, document.zoom)
        if document.showGrid, z >= 4 {
            cg.saveGState()
            cg.setStrokeColor(UIColor(white: 0.5, alpha: 0.5).cgColor)
            cg.setLineWidth(1 / z)
            let w = document.canvasWidth, h = document.canvasHeight
            for x in 0...w {
                cg.move(to: CGPoint(x: CGFloat(x), y: 0))
                cg.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(h)))
            }
            for y in 0...h {
                cg.move(to: CGPoint(x: 0, y: CGFloat(y)))
                cg.addLine(to: CGPoint(x: CGFloat(w), y: CGFloat(y)))
            }
            cg.strokePath()
            cg.restoreGState()
        }
        if let sel = document.selection {
            OverlayDrawing.drawAnts(cg, path: sel.path, zoom: z)
        }
        if let f = document.floating {
            OverlayDrawing.drawAnts(cg, path: f.canvasPath, zoom: z)
        }
        activeTool.drawOverlay(cg, toolContext)
    }

    // MARK: - Text box

    func syncTextBox() {
        if let editing = document.textEditing {
            if textBox == nil {
                let box = TextBoxView(frame: CGRect(origin: editing.origin, size: editing.size))
                box.onTextChange = { [weak self] text in
                    guard let self, var e = self.document.textEditing else { return }
                    if e.text != text {
                        e.text = text
                        self.document.textEditing = e
                    }
                }
                addSubview(box)
                textBox = box
                DispatchQueue.main.async { box.textView.becomeFirstResponder() }
            }
            textBox?.frame = CGRect(origin: editing.origin, size: editing.size)
            textBox?.apply(style: document.textStyle, color: document.primaryColor.uiColor,
                           background: document.textStyle.opaqueBackground ? document.secondaryColor.uiColor : nil,
                           zoom: document.zoom)
            if textBox?.textView.text != editing.text { textBox?.textView.text = editing.text }
        } else if let box = textBox {
            box.textView.resignFirstResponder()
            box.removeFromSuperview()
            textBox = nil
        }
    }

    // MARK: - Touch handling

    private func toolTouch(_ touch: UITouch) -> ToolTouch {
        let isPencil = touch.type == .pencil
        let force: CGFloat = isPencil && touch.maximumPossibleForce > 0 ? min(1, touch.force / touch.maximumPossibleForce) : 1
        return ToolTouch(location: touch.location(in: self), force: force, isPencil: isPencil, timestamp: touch.timestamp)
    }

    private func shouldIgnore(_ touch: UITouch) -> Bool {
        fingerPans && touch.type != .pencil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first, !shouldIgnore(touch) else { return }
        if let box = textBox, box.frame.contains(touch.location(in: self)), document.activeTool == .text {
            // Let the text view handle its own touches.
            return
        }
        activeTouch = touch
        let t = toolTouch(touch)
        document.cursorPosition = t.location
        activeTool.touchBegan(t, toolContext)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        let coalesced = event?.coalescedTouches(for: active) ?? [active]
        for c in coalesced {
            activeTool.touchMoved(toolTouch(c), toolContext)
        }
        document.cursorPosition = active.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        activeTouch = nil
        let t = toolTouch(active)
        activeTool.touchEnded(t, toolContext)
        document.cursorPosition = t.location
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        activeTouch = nil
        activeTool.touchCancelled(toolContext)
    }
}

// MARK: - Overlay

/// A non-zooming view layered above the scroll view that draws selection outlines, handles and previews.
final class OverlayView: UIView {
    weak var canvas: CanvasView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let canvas, let cg = UIGraphicsGetCurrentContext() else { return }
        let origin = canvas.convert(CGPoint.zero, to: self)
        let z = canvas.document.zoom
        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: z, y: z)
        canvas.drawOverlayContent(cg)
        cg.restoreGState()
    }
}

// MARK: - Text box

final class TextBoxView: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let border = CAShapeLayer()
    private let handle = UIView()
    var onTextChange: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        addSubview(textView)
        border.fillColor = nil
        border.strokeColor = UIColor.systemBlue.cgColor
        layer.addSublayer(border)
        handle.backgroundColor = .systemBlue
        handle.layer.borderColor = UIColor.white.cgColor
        addSubview(handle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var zoom: CGFloat = 1
    private var appliedStyle: TextStyle?
    private var appliedColor: UIColor?
    private var appliedBackground: UIColor?

    func apply(style: TextStyle, color: UIColor, background: UIColor?, zoom: CGFloat) {
        if self.zoom != zoom {
            self.zoom = zoom
            setNeedsLayout()
        }
        guard appliedStyle != style || appliedColor != color || appliedBackground != background else { return }
        appliedStyle = style
        appliedColor = color
        appliedBackground = background
        textView.font = style.uiFont
        textView.textColor = color
        textView.textAlignment = style.alignment.nsAlignment
        textView.backgroundColor = background ?? .clear
        var attrs = style.attributes(color: color, background: nil)
        attrs[.backgroundColor] = nil
        textView.typingAttributes = attrs
        if textView.text.isEmpty == false, textView.markedTextRange == nil {
            let selected = textView.selectedRange
            textView.attributedText = NSAttributedString(string: textView.text, attributes: attrs)
            textView.selectedRange = selected
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        border.frame = bounds
        border.lineWidth = 1 / zoom
        border.lineDashPattern = [NSNumber(value: Double(4 / zoom)), NSNumber(value: Double(3 / zoom))]
        border.path = UIBezierPath(rect: bounds).cgPath
        let s = 10 / zoom
        handle.frame = CGRect(x: bounds.maxX - s / 2, y: bounds.maxY - s / 2, width: s, height: s)
        handle.layer.borderWidth = 1 / zoom
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only the text view itself handles touches; the handle area is handled by the TextTool.
        let s = 14 / zoom
        if CGRect(x: bounds.maxX - s, y: bounds.maxY - s, width: s * 2, height: s * 2).contains(point) { return nil }
        return super.hitTest(point, with: event)
    }

    func textViewDidChange(_ textView: UITextView) {
        onTextChange?(textView.text)
    }
}
