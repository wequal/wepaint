import SwiftUI
import UIKit

/// Hosts the zoomable canvas inside a scroll view and the non-zooming overlay above it.
final class CanvasHostView: UIView, UIScrollViewDelegate {
    let document: PaintDocument
    let scrollView = UIScrollView()
    let canvas: CanvasView
    let overlay = OverlayView(frame: .zero)
    private var isSyncingZoom = false
    private var lastFitRequest = 0
    private var needsInitialFit = true

    init(document: PaintDocument) {
        self.document = document
        self.canvas = CanvasView(document: document)
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.87, alpha: 1)
        accessibilityIdentifier = "canvas"

        scrollView.delegate = self
        scrollView.minimumZoomScale = ZoomLevels.minimum
        scrollView.maximumZoomScale = ZoomLevels.maximum
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.addSubview(canvas)
        scrollView.contentSize = canvas.bounds.size
        addSubview(scrollView)

        overlay.canvas = canvas
        canvas.overlay = overlay
        addSubview(overlay)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        // Never hold back or cancel single-touch events destined for the canvas tools.
        twoFingerTap.delaysTouchesBegan = false
        twoFingerTap.delaysTouchesEnded = false
        twoFingerTap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(twoFingerTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        overlay.frame = bounds
        if needsInitialFit, bounds.width > 0, bounds.height > 0 {
            needsInitialFit = false
            fitToWindow()
        }
        centerContent()
        overlay.setNeedsDisplay()
    }

    // MARK: Zoom & layout

    private func centerContent() {
        let size = scrollView.contentSize
        let insetX = max((scrollView.bounds.width - size.width) / 2, 0)
        let insetY = max((scrollView.bounds.height - size.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func fitToWindow() {
        let cs = document.canvasSize
        guard cs.width > 0, cs.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let margin: CGFloat = 24
        let scale = min((bounds.width - margin) / cs.width, (bounds.height - margin) / cs.height)
        let z = min(ZoomLevels.maximum, max(ZoomLevels.minimum, scale))
        applyZoom(z, focus: nil, animated: false)
    }

    func applyZoom(_ z: CGFloat, focus: CGPoint?, animated: Bool) {
        isSyncingZoom = true
        defer { isSyncingZoom = false }
        let clamped = min(ZoomLevels.maximum, max(ZoomLevels.minimum, z))
        if let focus {
            let w = scrollView.bounds.width / clamped
            let h = scrollView.bounds.height / clamped
            let rect = CGRect(x: focus.x - w / 2, y: focus.y - h / 2, width: w, height: h)
            scrollView.zoom(to: rect, animated: animated)
        } else {
            scrollView.setZoomScale(clamped, animated: animated)
        }
        if !animated {
            scrollView.contentSize = canvas.frame.size
            centerContent()
            if abs(document.zoom - scrollView.zoomScale) > 0.0005 { document.zoom = scrollView.zoomScale }
        }
        overlay.setNeedsDisplay()
    }

    /// Reconciles the UIKit state with the document (called from updateUIView).
    func sync(fitRequest: Int) {
        if canvas.bounds.size != document.canvasSize {
            canvas.syncSize()
            scrollView.contentSize = canvas.frame.size
            centerContent()
        }
        if fitRequest != lastFitRequest {
            lastFitRequest = fitRequest
            if bounds.width > 0 { fitToWindow() } else { needsInitialFit = true }
        } else if !scrollView.isZooming, !scrollView.isZoomBouncing, !isAnimatingZoom,
                  abs(document.zoom - scrollView.zoomScale) > 0.0005 {
            let focus = document.zoomFocus
            document.zoomFocus = nil
            isAnimatingZoom = true
            applyZoom(document.zoom, focus: focus, animated: true)
        }
        canvas.syncTextBox()
        canvas.fingerPans = fingerPans
        scrollView.panGestureRecognizer.minimumNumberOfTouches = fingerPans ? 1 : 2
        let pointerKey = PointerKey(tool: document.activeTool, size: document.strokeWidth, zoom: document.zoom)
        if pointerKey != lastPointerKey {
            lastPointerKey = pointerKey
            canvas.refreshPointer()
        }
        overlay.setNeedsDisplay()
    }

    private struct PointerKey: Equatable {
        var tool: ToolKind
        var size: CGFloat
        var zoom: CGFloat
    }

    private var lastPointerKey: PointerKey?

    var fingerPans = false

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        overlay.setNeedsDisplay()
        if scrollView.isZooming, abs(document.zoom - scrollView.zoomScale) > 0.0005 {
            document.zoom = scrollView.zoomScale
        }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        isAnimatingZoom = false
        centerContent()
        if abs(document.zoom - scale) > 0.0005 { document.zoom = scale }
        overlay.setNeedsDisplay()
    }

    private var isAnimatingZoom = false

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        overlay.setNeedsDisplay()
    }

    @objc private func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
        guard document.activeTool == .magnifier else { return }
        let p = g.location(in: canvas)
        document.zoomOut(at: p)
    }
}

/// SwiftUI wrapper for the canvas host.
struct CanvasContainer: UIViewRepresentable {
    let document: PaintDocument
    let fingerPans: Bool
    // These are read so SwiftUI re-runs updateUIView when they change.
    let renderVersion: Int
    let zoom: CGFloat
    let canvasSize: CGSize
    let fitRequest: Int
    let textEditing: TextEditingState?
    let textStyle: TextStyle
    let primaryColor: RGBA
    let secondaryColor: RGBA
    let showGrid: Bool
    let activeTool: ToolKind
    let strokeWidth: CGFloat

    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView(document: document)
        host.fingerPans = fingerPans
        return host
    }

    func updateUIView(_ host: CanvasHostView, context: Context) {
        host.fingerPans = fingerPans
        host.sync(fitRequest: fitRequest)
    }
}

extension CanvasContainer {
    init(document: PaintDocument, fingerPans: Bool) {
        self.document = document
        self.fingerPans = fingerPans
        self.renderVersion = document.renderVersion
        self.zoom = document.zoom
        self.canvasSize = document.canvasSize
        self.fitRequest = document.fitToWindowRequest
        self.textEditing = document.textEditing
        self.textStyle = document.textStyle
        self.primaryColor = document.primaryColor
        self.secondaryColor = document.secondaryColor
        self.showGrid = document.showGrid
        self.activeTool = document.activeTool
        self.strokeWidth = document.strokeWidth
    }
}
