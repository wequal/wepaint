import SwiftUI

struct StatusBar: View {
    @Environment(PaintDocument.self) private var doc
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 10 : 18) {
            Label(cursorText, systemImage: "plus.viewfinder")
                .frame(minWidth: compact ? 70 : 110, alignment: .leading)
            if let selText {
                Label(selText, systemImage: "rectangle.dashed")
            }
            Label("\(doc.canvasWidth) × \(doc.canvasHeight)px", systemImage: "arrow.up.left.and.arrow.down.right")
            if let lbl = doc.history.undoLabel {
                Text("Last: \(lbl)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("lastAction")
            }
            Spacer()
            Button { doc.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.plain)
            Menu {
                ForEach(ZoomLevels.presets, id: \.self) { z in
                    Button(zoomLabel(z)) { doc.setZoom(z) }
                }
                Divider()
                Button("Fit to window") { doc.fitToWindow() }
            } label: {
                Text(zoomLabel(doc.zoom)).monospacedDigit().frame(minWidth: 48)
            }
            Button { doc.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var cursorText: String {
        guard let p = doc.cursorPosition else { return "—, —" }
        return "\(Int(p.x)), \(Int(p.y))px"
    }

    private var selText: String? {
        if let f = doc.floating { return "\(Int(f.frame.width)) × \(Int(f.frame.height))px" }
        if let s = doc.selection {
            let b = s.integralBounds(in: doc.canvasRect)
            return "\(Int(b.width)) × \(Int(b.height))px"
        }
        return nil
    }
}
