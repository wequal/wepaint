import SwiftUI

/// Primary/secondary swatches, the default palette, custom colors and a color editor.
struct ColorPaletteView: View {
    @Environment(PaintDocument.self) private var doc
    var compact = false

    @State private var editColor: Color = .black

    private var swatchSize: CGFloat { compact ? 26 : 20 }

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 10) {
            HStack(spacing: 6) {
                ColorTargetSwatch(title: "Color 1", target: .primary)
                ColorTargetSwatch(title: "Color 2", target: .secondary)
                Button { doc.swapColors() } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Swap colors")
            }
            paletteGrid
            if !doc.customColors.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(swatchSize), spacing: 3), count: 5), spacing: 3) {
                    ForEach(Array(doc.customColors.enumerated()), id: \.offset) { _, c in
                        swatch(c)
                    }
                }
            }
            ColorPicker(selection: $editColor, supportsOpacity: false) {
                Image(systemName: "paintpalette")
            }
            .labelsHidden()
            .onChange(of: editColor) { _, new in
                let rgba = RGBA(new)
                guard rgba != doc.primaryColor || doc.colorTarget == .secondary else { return }
                doc.applyColor(rgba)
                doc.addCustomColor(rgba)
            }
            .help("Edit colors")
        }
        .onAppear { editColor = doc.primaryColor.color }
    }

    private var paletteGrid: some View {
        LazyHGrid(rows: Array(repeating: GridItem(.fixed(swatchSize), spacing: 3), count: 2), spacing: 3) {
            ForEach(Array(PaintPalette.defaultColors.enumerated()), id: \.offset) { _, c in
                swatch(c)
            }
        }
        .frame(height: swatchSize * 2 + 3)
    }

    private func swatch(_ c: RGBA) -> some View {
        Button {
            doc.applyColor(c)
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(c.color)
                .frame(width: swatchSize, height: swatchSize)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(c.hexString)
    }
}

struct ColorTargetSwatch: View {
    @Environment(PaintDocument.self) private var doc
    let title: String
    let target: ColorTarget

    var body: some View {
        let color = target == .primary ? doc.primaryColor : doc.secondaryColor
        let selected = doc.colorTarget == target
        Button {
            doc.colorTarget = target
        } label: {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.color)
                    .frame(width: target == .primary ? 34 : 26, height: target == .primary ? 34 : 26)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.3), lineWidth: 0.5))
                Text(title).font(.system(size: 9))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// Size slider used by pencil/brush/eraser/shape tools.
struct SizeControl: View {
    @Environment(PaintDocument.self) private var doc
    var compact = false

    var body: some View {
        @Bindable var doc = doc
        HStack(spacing: 8) {
            Image(systemName: "lineweight").foregroundStyle(.secondary)
            Slider(value: $doc.strokeWidth, in: 1...100, step: 1)
                .frame(width: compact ? 120 : 160)
            Text("\(Int(doc.strokeWidth)) px")
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .leading)
            Menu {
                ForEach([1, 2, 3, 4, 5, 8, 10, 16, 24, 32, 48, 64], id: \.self) { s in
                    Button("\(s) px") { doc.strokeWidth = CGFloat(s) }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
        }
    }
}
