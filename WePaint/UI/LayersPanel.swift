import SwiftUI

struct LayersPanel: View {
    @Environment(PaintDocument.self) private var doc
    @State private var renamingID: UUID?
    @State private var renameText = ""

    /// Layers shown top-most first, like Paint.
    private var orderedLayers: [RasterLayer] { doc.layers.reversed() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                Button { doc.addLayer() } label: { Image(systemName: "plus") }
                    .help("Add layer")
                Button { doc.duplicateLayer() } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate layer")
                Button { doc.mergeDown() } label: { Image(systemName: "arrow.down.to.line.compact") }
                    .disabled((doc.layerIndex(of: doc.activeLayerID) ?? 0) == 0)
                    .help("Merge down")
                Button(role: .destructive) { doc.deleteLayer() } label: { Image(systemName: "trash") }
                    .disabled(doc.layers.count <= 1)
                    .help("Delete layer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List {
                ForEach(orderedLayers) { layer in
                    LayerRow(layer: layer, isActive: layer.id == doc.activeLayerID,
                             isRenaming: renamingID == layer.id, renameText: $renameText,
                             onBeginRename: { renamingID = layer.id; renameText = layer.name },
                             onCommitRename: { doc.renameLayer(layer.id, renameText); renamingID = nil })
                        .contentShape(Rectangle())
                        .onTapGesture { doc.selectLayer(layer.id) }
                        .listRowBackground(layer.id == doc.activeLayerID ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contextMenu {
                            Button("Rename") { renamingID = layer.id; renameText = layer.name }
                            Button("Duplicate") { doc.duplicateLayer(layer.id) }
                            Button("Merge down") { doc.mergeDown(layer.id) }
                                .disabled((doc.layerIndex(of: layer.id) ?? 0) == 0)
                            Button("Move up") { doc.moveLayerUp(layer.id) }
                                .disabled(doc.layerIndex(of: layer.id) == doc.layers.count - 1)
                            Button("Move down") { doc.moveLayerDown(layer.id) }
                                .disabled(doc.layerIndex(of: layer.id) == 0)
                            Button("Delete", role: .destructive) { doc.deleteLayer(layer.id) }
                                .disabled(doc.layers.count <= 1)
                        }
                }
                .onMove { source, destination in
                    // Convert from top-first display order to bottom-first storage order.
                    guard let first = source.first else { return }
                    let count = doc.layers.count
                    let from = count - 1 - first
                    let to = count - destination
                    doc.moveLayer(from: from, to: to)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            Divider()
            opacityControl
        }
        .background(.bar)
    }

    private var opacityControl: some View {
        let layer = doc.activeLayer
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Opacity").font(.caption)
                Spacer()
                Text("\(Int((layer.opacity * 100).rounded()))%").font(.caption.monospacedDigit())
            }
            Slider(value: Binding(get: { layer.opacity },
                                  set: { doc.setLayerOpacity(layer.id, $0, recordUndo: false) }),
                   in: 0...1, onEditingChanged: { editing in
                       if !editing { doc.setLayerOpacity(layer.id, layer.opacity, recordUndo: true) }
                   })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct LayerRow: View {
    @Environment(PaintDocument.self) private var doc
    let layer: RasterLayer
    let isActive: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                doc.setLayerVisible(layer.id, !layer.isVisible)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            LayerThumbnail(layer: layer, version: doc.renderVersion)
                .frame(width: 48, height: 36)
            if isRenaming {
                TextField("Layer name", text: $renameText, onCommit: onCommitRename)
                    .textFieldStyle(.roundedBorder)
            } else {
                VStack(alignment: .leading) {
                    Text(layer.name).font(.subheadline).lineLimit(1)
                    if layer.opacity < 1 {
                        Text("\(Int((layer.opacity * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .onTapGesture(count: 2) { onBeginRename() }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct LayerThumbnail: View {
    let layer: RasterLayer
    let version: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CheckerboardView()
                if let img = layer.image {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
        .id(version)
    }
}

struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let s: CGFloat = 6
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let dark = (row + col) % 2 == 0
                    context.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(dark ? Color(white: 0.8) : Color(white: 0.95)))
                    x += s; col += 1
                }
                y += s; row += 1
            }
        }
    }
}
