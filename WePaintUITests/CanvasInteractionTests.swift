import XCTest

/// Drives the real app with taps and drags and verifies the result by sampling screen pixels.
final class CanvasInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private var canvas: XCUIElement {
        let c = app.otherElements["canvas"]
        XCTAssertTrue(c.waitForExistence(timeout: 10), "canvas not found")
        return c
    }

    private func selectTool(_ id: String) {
        let button = app.buttons["tool.\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "tool button \(id) not found")
        // The compact toolbar scrolls horizontally; bring the button back into view if it scrolled away.
        let window = app.windows.firstMatch.frame
        if button.frame.minX < window.minX || button.frame.maxX > window.maxX {
            let bar = app.scrollViews.containing(.button, identifier: "tool.\(id)").firstMatch
            if button.frame.minX < window.minX { bar.swipeRight() } else { bar.swipeLeft() }
        }
        button.tap()
    }

    /// Returns the (r, g, b) of the screen pixel under a coordinate.
    private func pixel(at coordinate: XCUICoordinate) -> (Int, Int, Int) {
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { XCTFail("no screenshot"); return (-1, -1, -1) }
        let scaleX = CGFloat(cg.width) / image.size.width
        let scaleY = CGFloat(cg.height) / image.size.height
        let p = coordinate.screenPoint
        let x = Int(p.x * scaleX), y = Int(p.y * scaleY)
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (-1, -1, -1) }
        ctx.draw(cg, in: CGRect(x: -CGFloat(x), y: -CGFloat(cg.height - 1 - y), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func isWhite(_ c: (Int, Int, Int)) -> Bool { c.0 > 240 && c.1 > 240 && c.2 > 240 }
    private func isDark(_ c: (Int, Int, Int)) -> Bool { c.0 < 60 && c.1 < 60 && c.2 < 60 }

    /// Waits for the status bar's "Last: …" label to report the expected edit.
    private func assertLastAction(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["lastAction"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "status label missing", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, label.label != "Last: \(expected)" { usleep(200_000) }
        XCTAssertEqual(label.label, "Last: \(expected)", file: file, line: line)
    }

    func testFillTapFillsTheCanvas() {
        let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(isWhite(pixel(at: center)), "canvas should start white at the centre")
        selectTool("fill")
        XCTAssertTrue(app.staticTexts["toolTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["toolTitle"].label, "Fill with color", "tool button tap did not select the fill tool")
        center.tap()
        assertLastAction("Fill")
        let after = pixel(at: center)
        XCTAssertTrue(isDark(after), "fill should paint the canvas with Color 1 (black); got \(after)")
    }

    func testPencilDragDrawsALine() {
        selectTool("pencil")
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertTrue(isWhite(pixel(at: start)))
        start.press(forDuration: 0.1, thenDragTo: end)
        assertLastAction("Pencil")
        let mid = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let sampled = pixel(at: mid)
        XCTAssertTrue(isDark(sampled), "pencil drag should leave a black line; got \(sampled)")
    }

    func testFillStaysInsideADrawnRectangle() {
        // The compact toolbar has a Shapes tool button; the ribbon exposes the shape grid directly.
        if app.buttons["tool.shape"].waitForExistence(timeout: 2) {
            selectTool("shape")
        } else {
            let cell = app.buttons["shape.rectangle"]
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "rectangle shape cell not found")
            cell.tap()
        }
        // Keep everything inside the canvas band, which is letterboxed inside the host view in portrait.
        let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.42))
        let b = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.58))
        a.press(forDuration: 0.1, thenDragTo: b)
        // Tapping outside the pending shape commits it.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        assertLastAction("Rectangle")
        selectTool("fill")
        let inside = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let outside = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        XCTAssertTrue(isWhite(pixel(at: inside)), "inside before fill: \(pixel(at: inside))")
        // Also guards against the commit tap leaving a stray mark on the canvas.
        XCTAssertTrue(isWhite(pixel(at: outside)), "outside before fill: \(pixel(at: outside))")
        inside.tap()
        assertLastAction("Fill")
        XCTAssertTrue(isDark(pixel(at: inside)), "interior should be filled")
        XCTAssertTrue(isWhite(pixel(at: outside)), "fill must not leak past the rectangle outline")
    }
}
