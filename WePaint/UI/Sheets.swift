import SwiftUI

/// Paint's "Resize and Skew" dialog.
struct ResizeSkewSheet: View {
    let document: PaintDocument
    @Environment(\.dismiss) private var dismiss

    private enum Units: String, CaseIterable, Identifiable {
        case percentage, pixels
        var id: String { rawValue }
        var title: String { self == .percentage ? "Percentage" : "Pixels" }
    }

    @State private var units: Units = .percentage
    @State private var horizontal: Double = 100
    @State private var vertical: Double = 100
    @State private var maintainAspect = true
    @State private var skewH: Double = 0
    @State private var skewV: Double = 0
    /// Captured on appear: the selection size if a selection exists, otherwise the canvas size.
    @State private var baseWidth: Double = 1
    @State private var baseHeight: Double = 1
    @State private var targetsSelection = false

    var body: some View {
        NavigationStack {
            Form {
                Section(targetsSelection ? "Resize selection (\(Int(baseWidth)) × \(Int(baseHeight)) px)" : "Resize image") {
                    Picker("By", selection: $units) {
                        ForEach(Units.allCases) { u in Text(u.title).tag(u) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: units) { _, new in
                        switch new {
                        case .percentage:
                            horizontal = (horizontal / baseWidth * 100).rounded()
                            vertical = (vertical / baseHeight * 100).rounded()
                        case .pixels:
                            horizontal = (baseWidth * horizontal / 100).rounded()
                            vertical = (baseHeight * vertical / 100).rounded()
                        }
                    }
                    numberRow("Horizontal", value: $horizontal) { new in
                        if maintainAspect { vertical = (new * aspectRatio).rounded() }
                    }
                    numberRow("Vertical", value: $vertical) { new in
                        if maintainAspect { horizontal = (new / aspectRatio).rounded() }
                    }
                    Toggle("Maintain aspect ratio", isOn: $maintainAspect)
                    Text("Result: \(resultSize.0) × \(resultSize.1) px").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Skew (degrees)") {
                    numberRow("Horizontal", value: $skewH, range: -89...89) { _ in }
                    numberRow("Vertical", value: $skewV, range: -89...89) { _ in }
                }
            }
            .navigationTitle("Resize and Skew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { apply(); dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let s = document.selectionSize, s.width >= 1, s.height >= 1 {
                baseWidth = Double(s.width)
                baseHeight = Double(s.height)
                targetsSelection = true
            } else {
                baseWidth = Double(document.canvasWidth)
                baseHeight = Double(document.canvasHeight)
                targetsSelection = false
            }
        }
    }

    private var aspectRatio: Double {
        switch units {
        case .percentage: return 1
        case .pixels: return baseHeight / max(1, baseWidth)
        }
    }

    private var resultSize: (Int, Int) {
        switch units {
        case .percentage:
            return (Int((baseWidth * horizontal / 100).rounded()), Int((baseHeight * vertical / 100).rounded()))
        case .pixels:
            return (Int(horizontal), Int(vertical))
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = 1...8192, onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: Binding(get: { value.wrappedValue }, set: { v in
                let clamped = min(range.upperBound, max(range.lowerBound, v))
                value.wrappedValue = clamped
                onChange(clamped)
            }), format: .number)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
        }
    }

    private func apply() {
        let (w, h) = resultSize
        if w != Int(baseWidth) || h != Int(baseHeight), w >= 1, h >= 1 {
            document.resizeImage(toPixelWidth: w, height: h)
        }
        if abs(skewH) > 0.01 || abs(skewV) > 0.01 {
            document.skewImage(horizontalDegrees: skewH, verticalDegrees: skewV)
        }
    }
}

/// Paint's "Image Properties" dialog (canvas size, transparency, color mode).
struct ImagePropertiesSheet: View {
    let document: PaintDocument
    @Environment(\.dismiss) private var dismiss

    @State private var width: Double = 0
    @State private var height: Double = 0
    @State private var transparent = false
    @State private var blackAndWhite = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Canvas size (pixels)") {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("Width", value: $width, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("Height", value: $height, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    Button("Default (\(Int(PaintDocument.defaultSize.width)) × \(Int(PaintDocument.defaultSize.height)))") {
                        width = PaintDocument.defaultSize.width
                        height = PaintDocument.defaultSize.height
                    }
                }
                Section("Transparency") {
                    Toggle("Transparent background", isOn: $transparent)
                }
                Section("Colors") {
                    Toggle("Black and white", isOn: $blackAndWhite)
                    Text("Converts all layers to grayscale when applied.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("File") {
                    LabeledContent("Name", value: document.fileName)
                    LabeledContent("Layers", value: "\(document.layers.count)")
                    LabeledContent("Unsaved changes", value: document.isDirty ? "Yes" : "No")
                }
            }
            .navigationTitle("Image Properties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { apply(); dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            width = Double(document.canvasWidth)
            height = Double(document.canvasHeight)
            transparent = document.transparentBackground
        }
    }

    private func apply() {
        let w = Int(min(8192, max(1, width))), h = Int(min(8192, max(1, height)))
        if w != document.canvasWidth || h != document.canvasHeight {
            document.resizeCanvas(to: CGSize(width: w, height: h))
        }
        if transparent != document.transparentBackground {
            document.setTransparentBackground(transparent)
        }
        if blackAndWhite {
            document.convertToGrayscale()
        }
    }
}
