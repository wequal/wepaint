import SwiftUI

/// iPhone top bar: file/edit menus, undo/redo, layers and view controls.
struct CompactTopBar: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui

    var body: some View {
        HStack(spacing: 16) {
            Menu {
                FileMenuContent()
            } label: { Image(systemName: "doc.text") }
            Menu {
                Section("Clipboard") { ClipboardMenuContent() }
                Section("Selection") { SelectMenuContent() }
                Section("Image") { ImageMenuContent() }
            } label: { Image(systemName: "square.and.pencil") }
            UndoRedoButtons()
            Spacer()
            Text(doc.fileName + (doc.isDirty ? " •" : "")).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button { ui.showLayersSheet = true } label: { Image(systemName: "square.3.layers.3d") }
            Menu { ViewMenuContent() } label: { Image(systemName: "eye") }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// iPhone bottom bar: horizontally scrolling tool buttons plus colors.
struct CompactToolbar: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ToolKind.allCases) { kind in
                        Button {
                            if doc.activeTool == kind, kind == .brush || kind == .shape || kind == .select {
                                ui.showToolOptionsSheet = true
                            } else {
                                doc.activeTool = kind
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: iconFor(kind)).font(.title3)
                                Text(shortTitle(kind)).font(.system(size: 9))
                            }
                            .frame(width: 52, height: 46)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(doc.activeTool == kind ? Color.accentColor.opacity(0.25) : .clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tool.\(kind.rawValue)")
                    }
                }
                .padding(.horizontal, 6)
            }
            Divider().frame(height: 36)
            Button {
                ui.showColorsSheet = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 5).fill(doc.secondaryColor.color)
                        .frame(width: 26, height: 26).offset(x: 8, y: 8)
                    RoundedRectangle(cornerRadius: 5).fill(doc.primaryColor.color)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.3), lineWidth: 0.5))
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 56)
        .background(.bar)
    }

    private func iconFor(_ kind: ToolKind) -> String {
        switch kind {
        case .brush: return doc.brushKind.systemImage
        case .shape: return doc.shapeKind.systemImage
        case .select: return doc.selectMode.systemImage
        default: return kind.systemImage
        }
    }

    private func shortTitle(_ kind: ToolKind) -> String {
        switch kind {
        case .fill: return "Fill"
        case .colorPicker: return "Picker"
        case .magnifier: return "Zoom"
        case .brush: return "Brush"
        case .shape: return "Shape"
        default: return kind.title
        }
    }
}

/// Sheet with the full color palette for compact layouts.
struct ColorsSheet: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(\.dismiss) private var dismiss
    @State private var editColor: Color = .black

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 20) {
                    ColorTargetSwatch(title: "Color 1", target: .primary)
                    ColorTargetSwatch(title: "Color 2", target: .secondary)
                    Button { doc.swapColors() } label: { Label("Swap", systemImage: "arrow.left.arrow.right") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                }
                Text("Palette").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 10), spacing: 8) {
                    ForEach(Array(PaintPalette.defaultColors.enumerated()), id: \.offset) { _, c in
                        swatch(c)
                    }
                }
                if !doc.customColors.isEmpty {
                    Text("Custom colors").font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 10), spacing: 8) {
                        ForEach(Array(doc.customColors.enumerated()), id: \.offset) { _, c in
                            swatch(c)
                        }
                    }
                }
                ColorPicker("Edit colors", selection: $editColor, supportsOpacity: false)
                    .onChange(of: editColor) { _, new in
                        let rgba = RGBA(new)
                        guard rgba != doc.primaryColor || doc.colorTarget == .secondary else { return }
                        doc.applyColor(rgba)
                        doc.addCustomColor(rgba)
                    }
                Spacer()
            }
            .padding()
            .navigationTitle("Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { editColor = doc.primaryColor.color }
        }
        .presentationDetents([.medium, .large])
    }

    private func swatch(_ c: RGBA) -> some View {
        Button { doc.applyColor(c) } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(c.color)
                .aspectRatio(1, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Sheet with pickers for brushes / shapes / selection in compact layouts.
struct ToolOptionsSheet: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var doc = doc
        NavigationStack {
            Form {
                switch doc.activeTool {
                case .brush:
                    Section("Brush") {
                        ForEach(BrushKind.allCases) { b in
                            Button {
                                doc.brushKind = b
                            } label: {
                                HStack {
                                    Label(b.title, systemImage: b.systemImage)
                                    Spacer()
                                    if doc.brushKind == b { Image(systemName: "checkmark") }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                case .shape:
                    Section("Shape") {
                        ShapeGrid { kind in doc.shapeKind = kind }
                    }
                    Section("Style") {
                        Picker("Outline", selection: $doc.shapeOutline) {
                            ForEach(ShapeOutlineStyle.allCases) { s in Text(s.title).tag(s) }
                        }
                        Picker("Fill", selection: $doc.shapeFill) {
                            ForEach(ShapeFillStyle.allCases) { s in Text(s.title).tag(s) }
                        }
                    }
                case .select:
                    Section("Selection") {
                        Picker("Shape", selection: $doc.selectMode) {
                            ForEach(SelectMode.allCases) { m in Label(m.title, systemImage: m.systemImage).tag(m) }
                        }
                        Toggle("Transparent selection", isOn: $doc.transparentSelection)
                        Button("Select all") { doc.selectAll(); dismiss() }
                        Button("Invert selection") { doc.invertSelection(); dismiss() }.disabled(doc.selection == nil)
                        Button("Crop to selection") { doc.cropToSelection(); dismiss() }.disabled(!doc.hasSelection)
                        Button("Delete selection", role: .destructive) { doc.deleteSelection(); dismiss() }.disabled(!doc.hasSelection)
                    }
                    Section("Transform selection") {
                        Button { doc.rotate(.clockwise90) } label: { Label("Rotate right 90°", systemImage: "rotate.right") }
                        Button { doc.rotate(.counterClockwise90) } label: { Label("Rotate left 90°", systemImage: "rotate.left") }
                        Button { doc.rotate(.half) } label: { Label("Rotate 180°", systemImage: "arrow.triangle.2.circlepath") }
                        Button { doc.flip(.horizontal) } label: { Label("Flip horizontal", systemImage: "arrow.left.and.right") }
                        Button { doc.flip(.vertical) } label: { Label("Flip vertical", systemImage: "arrow.up.and.down") }
                        Button { dismiss(); ui.showResizeSkew = true } label: { Label("Resize and skew", systemImage: "arrow.up.left.and.arrow.down.right") }
                    }
                    .disabled(!doc.hasSelection)
                default:
                    EmptyView()
                }
                if doc.activeTool.usesSize {
                    Section("Size") {
                        Slider(value: $doc.strokeWidth, in: 1...100, step: 1)
                        Text("\(Int(doc.strokeWidth)) px")
                    }
                }
            }
            .navigationTitle(doc.activeTool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
