import SwiftUI

/// File menu contents (shared by the ribbon and the compact top bar).
struct FileMenuContent: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui

    var body: some View {
        Button { ui.newImage(doc) } label: { Label("New", systemImage: "doc") }
        Menu {
            Button { ui.openFromPhotos(doc, purpose: .open) } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
            Button { ui.openFromFiles(doc, purpose: .open) } label: { Label("From Files", systemImage: "folder") }
        } label: { Label("Open", systemImage: "folder") }
        Menu {
            Button { ui.openFromPhotos(doc, purpose: .pasteFrom) } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
            Button { ui.openFromFiles(doc, purpose: .pasteFrom) } label: { Label("From Files", systemImage: "folder") }
        } label: { Label("Paste from", systemImage: "square.and.arrow.down.on.square") }
        Divider()
        Button { ui.saveToPhotos(doc) } label: { Label("Save to Photos", systemImage: "square.and.arrow.down") }
        Menu {
            ForEach(ExportFormat.allCases) { f in
                Button(f.title) { ui.exportImage(doc, format: f) }
            }
        } label: { Label("Save as", systemImage: "square.and.arrow.down.on.square") }
        ShareImageButton()
        Divider()
        Button { ui.showProperties = true } label: { Label("Image properties", systemImage: "info.circle") }
    }
}

/// Lazily encodes the flattened image when the share sheet asks for it.
struct ShareableImage: Transferable {
    let document: PaintDocument
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.document.exportData(format: .png) ?? Data()
        }
        .suggestedFileName { $0.name + ".png" }
    }
}

struct ShareImageButton: View {
    @Environment(PaintDocument.self) private var doc

    var body: some View {
        ShareLink(item: ShareableImage(document: doc, name: doc.exportBaseName), preview: SharePreview(doc.exportBaseName)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}

struct ClipboardMenuContent: View {
    @Environment(PaintDocument.self) private var doc

    var body: some View {
        Button { doc.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
        Button { doc.cutSelection() } label: { Label("Cut", systemImage: "scissors") }
            .disabled(!doc.hasSelection)
        Button { doc.copySelection() } label: { Label("Copy", systemImage: "doc.on.doc") }
    }
}

struct SelectMenuContent: View {
    @Environment(PaintDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        Picker("Selection shape", selection: $doc.selectMode) {
            ForEach(SelectMode.allCases) { m in
                Label(m.title, systemImage: m.systemImage).tag(m)
            }
        }
        .onChange(of: doc.selectMode) { _, _ in if doc.activeTool != .select { doc.activeTool = .select } }
        Divider()
        Button { doc.selectAll() } label: { Label("Select all", systemImage: "square.dashed") }
        Button { doc.invertSelection() } label: { Label("Invert selection", systemImage: "rectangle.inset.filled.and.person.filled") }
            .disabled(doc.selection == nil)
        Button(role: .destructive) { doc.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
            .disabled(!doc.hasSelection)
        Toggle(isOn: $doc.transparentSelection) { Label("Transparent selection", systemImage: "checkerboard.rectangle") }
    }
}

struct ImageMenuContent: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui

    var body: some View {
        Button { doc.cropToSelection() } label: { Label("Crop", systemImage: "crop") }
            .disabled(!doc.hasSelection)
        Button { ui.showResizeSkew = true } label: { Label("Resize and skew", systemImage: "arrow.up.left.and.arrow.down.right") }
        Menu {
            Button { doc.rotate(.clockwise90) } label: { Label("Rotate right 90°", systemImage: "rotate.right") }
            Button { doc.rotate(.counterClockwise90) } label: { Label("Rotate left 90°", systemImage: "rotate.left") }
            Button { doc.rotate(.half) } label: { Label("Rotate 180°", systemImage: "arrow.triangle.2.circlepath") }
        } label: { Label("Rotate", systemImage: "rotate.right") }
        Menu {
            Button { doc.flip(.vertical) } label: { Label("Flip vertical", systemImage: "arrow.up.and.down") }
            Button { doc.flip(.horizontal) } label: { Label("Flip horizontal", systemImage: "arrow.left.and.right") }
        } label: { Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
        Divider()
        Button { ui.showProperties = true } label: { Label("Image properties", systemImage: "info.circle") }
    }
}

struct ViewMenuContent: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui

    var body: some View {
        @Bindable var doc = doc
        @Bindable var ui = ui
        Button { doc.zoomIn() } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
        Button { doc.zoomOut() } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
        Button { doc.setZoom(1) } label: { Label("100%", systemImage: "1.magnifyingglass") }
        Button { doc.fitToWindow() } label: { Label("Fit to window", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
        Menu {
            ForEach(ZoomLevels.presets, id: \.self) { z in
                Button(zoomLabel(z)) { doc.setZoom(z) }
            }
        } label: { Label("Zoom level", systemImage: "magnifyingglass") }
        Divider()
        Toggle(isOn: $doc.showGrid) { Label("Gridlines", systemImage: "grid") }
        Toggle(isOn: $doc.showStatusBar) { Label("Status bar", systemImage: "rectangle.bottomthird.inset.filled") }
        Toggle(isOn: $doc.showLayersPanel) { Label("Layers panel", systemImage: "square.3.layers.3d") }
        Toggle(isOn: $ui.fingerPans) { Label("Finger pans, Pencil draws", systemImage: "hand.draw") }
    }
}

func zoomLabel(_ z: CGFloat) -> String {
    let pct = z * 100
    if pct == pct.rounded() { return "\(Int(pct))%" }
    return String(format: "%.1f%%", pct)
}

struct UndoRedoButtons: View {
    @Environment(PaintDocument.self) private var doc

    var body: some View {
        Button { doc.undo() } label: { Image(systemName: "arrow.uturn.backward") }
            .disabled(!doc.history.canUndo)
            .help(doc.history.undoLabel.map { "Undo \($0)" } ?? "Undo")
        Button { doc.redo() } label: { Image(systemName: "arrow.uturn.forward") }
            .disabled(!doc.history.canRedo)
            .help(doc.history.redoLabel.map { "Redo \($0)" } ?? "Redo")
    }
}
