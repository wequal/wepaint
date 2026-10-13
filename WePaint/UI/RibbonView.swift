import SwiftUI

/// The iPad ribbon: a title row with file/undo controls and a row of tool groups like Windows 11 Paint.
struct RibbonView: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    group("Clipboard") {
                        Menu { ClipboardMenuContent() } label: {
                            bigLabel("Paste", systemImage: "doc.on.clipboard")
                        }
                        VStack(spacing: 6) {
                            iconButton("scissors", help: "Cut") { doc.cutSelection() }.disabled(!doc.hasSelection)
                            iconButton("doc.on.doc", help: "Copy") { doc.copySelection() }
                        }
                    }
                    group("Image") {
                        Menu { SelectMenuContent() } label: {
                            bigLabel("Select", systemImage: doc.selectMode.systemImage, active: doc.activeTool == .select)
                        } primaryAction: {
                            doc.activeTool = .select
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            smallMenuButton("Crop", systemImage: "crop") { doc.cropToSelection() }
                                .disabled(!doc.hasSelection)
                            smallMenuButton("Resize", systemImage: "arrow.up.left.and.arrow.down.right") { ui.showResizeSkew = true }
                            Menu {
                                Button("Rotate right 90°") { doc.rotate(.clockwise90) }
                                Button("Rotate left 90°") { doc.rotate(.counterClockwise90) }
                                Button("Rotate 180°") { doc.rotate(.half) }
                                Divider()
                                Button("Flip vertical") { doc.flip(.vertical) }
                                Button("Flip horizontal") { doc.flip(.horizontal) }
                            } label: {
                                Label("Rotate", systemImage: "rotate.right").font(.caption)
                            }
                        }
                    }
                    group("Tools") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 3), spacing: 4) {
                            ForEach([ToolKind.pencil, .fill, .text, .eraser, .colorPicker, .magnifier]) { kind in
                                toolButton(kind)
                            }
                        }
                    }
                    group("Brushes") {
                        Menu {
                            @Bindable var doc = doc
                            Picker("Brush", selection: $doc.brushKind) {
                                ForEach(BrushKind.allCases) { b in
                                    Label(b.title, systemImage: b.systemImage).tag(b)
                                }
                            }
                        } label: {
                            bigLabel("Brushes", systemImage: doc.brushKind.systemImage, active: doc.activeTool == .brush)
                        } primaryAction: {
                            doc.activeTool = .brush
                        }
                    }
                    group("Shapes") {
                        ShapeGrid(cellSize: 26, columns: 8, spacing: 3) { kind in
                            doc.shapeKind = kind
                            doc.activeTool = .shape
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            @Bindable var doc = doc
                            Picker("Outline", selection: $doc.shapeOutline) {
                                ForEach(ShapeOutlineStyle.allCases) { s in Text(s.title).tag(s) }
                            }
                            .font(.caption)
                            Picker("Fill", selection: $doc.shapeFill) {
                                ForEach(ShapeFillStyle.allCases) { s in Text(s.title).tag(s) }
                            }
                            .font(.caption)
                        }
                        .frame(width: 130)
                    }
                    group("Size") {
                        Menu {
                            ForEach([1, 2, 3, 4, 5, 8, 10, 16, 24, 32, 48, 64], id: \.self) { s in
                                Button("\(s) px") { doc.strokeWidth = CGFloat(s) }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Capsule().fill(Color.primary).frame(width: 28, height: max(1, min(16, doc.strokeWidth / 2)))
                                Text("\(Int(doc.strokeWidth)) px").font(.caption)
                            }
                            .frame(width: 56, height: 56)
                        }
                    }
                    group("Colors") {
                        ColorPaletteView()
                    }
                    group("Layers") {
                        Button {
                            doc.showLayersPanel.toggle()
                        } label: {
                            bigLabel("Layers", systemImage: "square.3.layers.3d", active: doc.showLayersPanel)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 118)
            .background(.bar)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 14) {
            Menu { FileMenuContent() } label: {
                Label("File", systemImage: "doc.text").labelStyle(.titleOnly).font(.subheadline.weight(.semibold))
            }
            Menu { ViewMenuContent() } label: {
                Text("View").font(.subheadline.weight(.semibold))
            }
            Menu { ImageMenuContent() } label: {
                Text("Image").font(.subheadline.weight(.semibold))
            }
            UndoRedoButtons()
            Spacer()
            Text("\(doc.fileName)\(doc.isDirty ? " •" : "") — WePaint").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button { ui.saveToPhotos(doc) } label: { Image(systemName: "square.and.arrow.down") }
                .help("Save to Photos")
            ShareImageButton().labelStyle(.iconOnly)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) { content() }
                .frame(maxHeight: .infinity)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .overlay(alignment: .trailing) { Divider().padding(.vertical, 4) }
    }

    private func bigLabel(_ title: String, systemImage: String, active: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title2)
            Text(title).font(.caption)
        }
        .frame(width: 60, height: 56)
        .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.accentColor.opacity(0.2) : .clear))
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func smallMenuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.caption)
        }
        .buttonStyle(.plain)
    }

    private func toolButton(_ kind: ToolKind) -> some View {
        Button {
            doc.activeTool = kind
        } label: {
            Image(systemName: kind.systemImage)
                .font(.body)
                .frame(width: 36, height: 32)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(doc.activeTool == kind ? Color.accentColor.opacity(0.25) : Color.clear))
        }
        .buttonStyle(.plain)
        .help(kind.title)
        .accessibilityIdentifier("tool.\(kind.rawValue)")
    }
}
