import SwiftUI

/// Context-sensitive options for the active tool, shown under the ribbon / above the compact toolbar.
struct ToolOptionsBar: View {
    @Environment(PaintDocument.self) private var doc
    var compact = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Label(doc.activeTool.title, systemImage: doc.activeTool.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                Divider().frame(height: 22)
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 44)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var doc = doc
        switch doc.activeTool {
        case .select:
            Picker("Mode", selection: $doc.selectMode) {
                ForEach(SelectMode.allCases) { m in
                    Image(systemName: m.systemImage).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            Toggle(isOn: $doc.transparentSelection) { Text("Transparent") }
                .toggleStyle(.button)
            Button("Select all") { doc.selectAll() }
            Button("Invert") { doc.invertSelection() }.disabled(doc.selection == nil)
            Button("Crop") { doc.cropToSelection() }.disabled(!doc.hasSelection)
            Button("Delete", role: .destructive) { doc.deleteSelection() }.disabled(!doc.hasSelection)
            Divider().frame(height: 22)
            Button { doc.cutSelection() } label: { Image(systemName: "scissors") }.disabled(!doc.hasSelection)
            Button { doc.copySelection() } label: { Image(systemName: "doc.on.doc") }
            Button { doc.paste() } label: { Image(systemName: "doc.on.clipboard") }
        case .pencil, .eraser:
            SizeControl(compact: compact)
            if doc.activeTool == .eraser {
                Text(doc.eraseColor == nil ? "Erases to transparent" : "Erases to Color 2")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .fill:
            HStack(spacing: 8) {
                Text("Tolerance").font(.caption)
                Slider(value: Binding(get: { Double(doc.fillTolerance) }, set: { doc.fillTolerance = Int($0) }), in: 0...100, step: 1)
                    .frame(width: compact ? 120 : 160)
                Text("\(doc.fillTolerance)%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .leading)
            }
        case .text:
            TextOptions(compact: compact)
        case .colorPicker:
            Text("Tap the canvas to pick a color into \(doc.colorTarget == .primary ? "Color 1" : "Color 2").")
                .font(.caption).foregroundStyle(.secondary)
        case .magnifier:
            Button { doc.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
            Button { doc.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
            Button("100%") { doc.setZoom(1) }
            Button("Fit") { doc.fitToWindow() }
            Text("Tap to zoom in, two-finger tap to zoom out.").font(.caption).foregroundStyle(.secondary)
        case .brush:
            BrushPicker()
            Divider().frame(height: 22)
            SizeControl(compact: compact)
        case .shape:
            ShapePicker()
            Picker("Outline", selection: $doc.shapeOutline) {
                ForEach(ShapeOutlineStyle.allCases) { s in Text(s.title).tag(s) }
            }
            .frame(width: compact ? 110 : 140)
            Picker("Fill", selection: $doc.shapeFill) {
                ForEach(ShapeFillStyle.allCases) { s in Text(s.title).tag(s) }
            }
            .frame(width: compact ? 100 : 130)
            Divider().frame(height: 22)
            SizeControl(compact: compact)
        }
    }
}

struct BrushPicker: View {
    @Environment(PaintDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        Menu {
            Picker("Brush", selection: $doc.brushKind) {
                ForEach(BrushKind.allCases) { b in
                    Label(b.title, systemImage: b.systemImage).tag(b)
                }
            }
        } label: {
            Label(doc.brushKind.title, systemImage: doc.brushKind.systemImage)
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct ShapePicker: View {
    @Environment(PaintDocument.self) private var doc
    @State private var showGrid = false

    var body: some View {
        Button {
            showGrid.toggle()
        } label: {
            Label(doc.shapeKind.title, systemImage: doc.shapeKind.systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $showGrid) {
            ShapeGrid { kind in
                doc.shapeKind = kind
                showGrid = false
            }
            .padding(12)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct ShapeGrid: View {
    @Environment(PaintDocument.self) private var doc
    var cellSize: CGFloat = 44
    var columns: Int = 6
    var spacing: CGFloat = 6
    let onPick: (ShapeKind) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(ShapeKind.allCases) { kind in
                Button { onPick(kind) } label: {
                    Image(systemName: kind.systemImage)
                        .font(cellSize >= 40 ? .title3 : .footnote)
                        .frame(width: cellSize, height: cellSize)
                        .background(RoundedRectangle(cornerRadius: cellSize >= 40 ? 8 : 5)
                            .fill(kind == doc.shapeKind ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(kind.title)
            }
        }
    }
}

struct TextOptions: View {
    @Environment(PaintDocument.self) private var doc
    var compact = false

    var body: some View {
        @Bindable var doc = doc
        Picker("Font", selection: $doc.textStyle.fontName) {
            ForEach(TextStyle.fontChoices, id: \.self) { f in
                Text(f).tag(f)
            }
        }
        .frame(width: compact ? 130 : 170)
        Picker("Size", selection: $doc.textStyle.fontSize) {
            ForEach(TextStyle.sizeChoices, id: \.self) { s in
                Text("\(Int(s))").tag(s)
            }
        }
        .frame(width: 70)
        Toggle(isOn: $doc.textStyle.bold) { Image(systemName: "bold") }.toggleStyle(.button)
        Toggle(isOn: $doc.textStyle.italic) { Image(systemName: "italic") }.toggleStyle(.button)
        Toggle(isOn: $doc.textStyle.underline) { Image(systemName: "underline") }.toggleStyle(.button)
        Toggle(isOn: $doc.textStyle.strikethrough) { Image(systemName: "strikethrough") }.toggleStyle(.button)
        Picker("Alignment", selection: $doc.textStyle.alignment) {
            ForEach(TextAlignmentOption.allCases) { a in
                Image(systemName: a.systemImage).tag(a)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
        Toggle(isOn: $doc.textStyle.opaqueBackground) { Text("Opaque") }.toggleStyle(.button)
        if doc.textEditing != nil {
            Button("Done") { doc.toolHost?.commitPendingToolWork() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
