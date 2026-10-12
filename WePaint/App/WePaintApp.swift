import SwiftUI

@main
struct WePaintApp: App {
    @State private var document = PaintDocument()
    @State private var ui = AppUIState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(document)
                .environment(ui)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { ui.newImage(document) }.keyboardShortcut("n", modifiers: .command)
                Button("Open from Files…") { ui.openFromFiles(document, purpose: .open) }.keyboardShortcut("o", modifiers: .command)
                Button("Open from Photos…") { ui.openFromPhotos(document, purpose: .open) }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Save as PNG…") { ui.exportImage(document, format: .png) }.keyboardShortcut("s", modifiers: .command)
                Button("Save as JPEG…") { ui.exportImage(document, format: .jpeg) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Save to Photos") { ui.saveToPhotos(document) }.keyboardShortcut("s", modifiers: [.command, .option])
                Divider()
                Button("Image Properties…") { ui.showProperties = true }.keyboardShortcut("e", modifiers: .command)
                Button("Resize and Skew…") { ui.showResizeSkew = true }.keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { document.undo() }.keyboardShortcut("z", modifiers: .command)
                    .disabled(!document.history.canUndo)
                Button("Redo") { document.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!document.history.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { document.cutSelection() }.keyboardShortcut("x", modifiers: .command)
                Button("Copy") { document.copySelection() }.keyboardShortcut("c", modifiers: .command)
                Button("Paste") { document.paste() }.keyboardShortcut("v", modifiers: .command)
                Button("Delete") { document.deleteSelection() }.keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button("Select All") { document.selectAll() }.keyboardShortcut("a", modifiers: .command)
                Button("Invert Selection") { document.invertSelection() }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Deselect") { document.deselect() }.keyboardShortcut("d", modifiers: .command)
                Button("Crop") { document.cropToSelection() }.keyboardShortcut("x", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Zoom In") { document.zoomIn() }.keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { document.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { document.setZoom(1) }.keyboardShortcut("0", modifiers: .command)
                Button("Fit to Window") { document.fitToWindow() }.keyboardShortcut("0", modifiers: [.command, .shift])
                Divider()
                Button(document.showGrid ? "Hide Gridlines" : "Show Gridlines") { document.showGrid.toggle() }.keyboardShortcut("g", modifiers: .command)
                Button(document.showLayersPanel ? "Hide Layers" : "Show Layers") { document.showLayersPanel.toggle() }.keyboardShortcut("l", modifiers: .command)
            }
            CommandMenu("Image") {
                Button("Rotate Right 90°") { document.rotate(.clockwise90) }.keyboardShortcut("r", modifiers: .command)
                Button("Rotate Left 90°") { document.rotate(.counterClockwise90) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Rotate 180°") { document.rotate(.half) }
                Button("Flip Horizontal") { document.flip(.horizontal) }
                Button("Flip Vertical") { document.flip(.vertical) }
                Divider()
                Button("Add Layer") { document.addLayer() }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Duplicate Layer") { document.duplicateLayer() }.keyboardShortcut("j", modifiers: .command)
                Button("Merge Down") { document.mergeDown() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Tools") {
                ForEach(Array(ToolKind.allCases.enumerated()), id: \.element) { index, kind in
                    Button(kind.title) { document.activeTool = kind }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                }
            }
        }
    }
}
