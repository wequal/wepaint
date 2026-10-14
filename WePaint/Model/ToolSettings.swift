import SwiftUI

enum ToolKind: String, CaseIterable, Identifiable {
    case select, pencil, fill, text, eraser, colorPicker, magnifier, brush, shape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .pencil: return "Pencil"
        case .fill: return "Fill with color"
        case .text: return "Text"
        case .eraser: return "Eraser"
        case .colorPicker: return "Color picker"
        case .magnifier: return "Magnifier"
        case .brush: return "Brushes"
        case .shape: return "Shapes"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "rectangle.dashed"
        case .pencil: return "pencil"
        case .fill: return "drop.fill"
        case .text: return "textformat"
        case .eraser: return "eraser"
        case .colorPicker: return "eyedropper"
        case .magnifier: return "magnifyingglass"
        case .brush: return "paintbrush.pointed"
        case .shape: return "square.on.circle"
        }
    }

    /// Whether the size slider applies to this tool.
    var usesSize: Bool {
        switch self {
        case .pencil, .eraser, .brush, .shape: return true
        default: return false
        }
    }
}

enum BrushKind: String, CaseIterable, Identifiable {
    case brush, calligraphy1, calligraphy2, airbrush, oil, crayon, marker, naturalPencil, watercolor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brush: return "Brush"
        case .calligraphy1: return "Calligraphy brush 1"
        case .calligraphy2: return "Calligraphy brush 2"
        case .airbrush: return "Airbrush"
        case .oil: return "Oil brush"
        case .crayon: return "Crayon"
        case .marker: return "Marker"
        case .naturalPencil: return "Natural pencil"
        case .watercolor: return "Watercolor brush"
        }
    }

    var systemImage: String {
        switch self {
        case .brush: return "paintbrush.pointed.fill"
        case .calligraphy1: return "pencil.tip"
        case .calligraphy2: return "pencil.tip.crop.circle"
        case .airbrush: return "aqi.medium"
        case .oil: return "paintbrush.fill"
        case .crayon: return "scribble"
        case .marker: return "highlighter"
        case .naturalPencil: return "pencil.line"
        case .watercolor: return "drop.halffull"
        }
    }
}

enum ShapeKind: String, CaseIterable, Identifiable {
    case line, curve, oval, rectangle, roundedRectangle, polygon, triangle, rightTriangle, diamond,
         pentagon, hexagon, rightArrow, leftArrow, upArrow, downArrow, star4, star5, star6,
         roundedCallout, ovalCallout, cloudCallout, heart, lightning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "Line"
        case .curve: return "Curve"
        case .oval: return "Oval"
        case .rectangle: return "Rectangle"
        case .roundedRectangle: return "Rounded rectangle"
        case .polygon: return "Polygon"
        case .triangle: return "Triangle"
        case .rightTriangle: return "Right triangle"
        case .diamond: return "Diamond"
        case .pentagon: return "Pentagon"
        case .hexagon: return "Hexagon"
        case .rightArrow: return "Right arrow"
        case .leftArrow: return "Left arrow"
        case .upArrow: return "Up arrow"
        case .downArrow: return "Down arrow"
        case .star4: return "Four-point star"
        case .star5: return "Five-point star"
        case .star6: return "Six-point star"
        case .roundedCallout: return "Rounded rectangular callout"
        case .ovalCallout: return "Oval callout"
        case .cloudCallout: return "Cloud callout"
        case .heart: return "Heart"
        case .lightning: return "Lightning"
        }
    }

    var systemImage: String {
        switch self {
        case .line: return "line.diagonal"
        case .curve: return "scribble.variable"
        case .oval: return "oval"
        case .rectangle: return "rectangle"
        case .roundedRectangle: return "rectangle.roundedtop"
        case .polygon: return "pentagon.lefthalf.filled"
        case .triangle: return "triangle"
        case .rightTriangle: return "triangle.righthalf.filled"
        case .diamond: return "diamond"
        case .pentagon: return "pentagon"
        case .hexagon: return "hexagon"
        case .rightArrow: return "arrowshape.right"
        case .leftArrow: return "arrowshape.left"
        case .upArrow: return "arrowshape.up"
        case .downArrow: return "arrowshape.down"
        case .star4: return "sparkle"
        case .star5: return "star"
        case .star6: return "staroflife"
        case .roundedCallout: return "bubble.left"
        case .ovalCallout: return "ellipsis.bubble"
        case .cloudCallout: return "cloud"
        case .heart: return "heart"
        case .lightning: return "bolt"
        }
    }

    var isOpenPath: Bool { self == .line || self == .curve }
}

enum ShapeOutlineStyle: String, CaseIterable, Identifiable {
    case none, solid
    var id: String { rawValue }
    var title: String { self == .none ? "No outline" : "Solid color" }
}

enum ShapeFillStyle: String, CaseIterable, Identifiable {
    case none, solid
    var id: String { rawValue }
    var title: String { self == .none ? "No fill" : "Solid color" }
}

enum SelectMode: String, CaseIterable, Identifiable {
    case rectangle, freeform
    var id: String { rawValue }
    var title: String { self == .rectangle ? "Rectangle" : "Free-form" }
    var systemImage: String { self == .rectangle ? "rectangle.dashed" : "lasso" }
}

enum ColorTarget: String, CaseIterable, Identifiable {
    case primary, secondary
    var id: String { rawValue }
}

enum TextAlignmentOption: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
    var systemImage: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

struct TextStyle: Equatable {
    var fontName: String = "Helvetica"
    var fontSize: CGFloat = 24
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var alignment: TextAlignmentOption = .left
    var opaqueBackground = false

    static let fontChoices: [String] = [
        "Helvetica", "Arial", "Times New Roman", "Courier New", "Georgia", "Verdana",
        "Trebuchet MS", "Avenir", "Futura", "Gill Sans", "Palatino", "Menlo", "Chalkboard SE", "Marker Felt", "Noteworthy",
    ]

    static let sizeChoices: [CGFloat] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72, 96, 128, 160, 192, 224, 256]

    var uiFont: UIFont {
        var font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let desc = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: desc, size: fontSize)
        }
        return font
    }

    func attributes(color: UIColor, background: UIColor?) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment.nsAlignment
        var attrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let background { attrs[.backgroundColor] = background }
        return attrs
    }
}

enum ZoomLevels {
    static let presets: [CGFloat] = [0.125, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
    static let minimum: CGFloat = 0.125
    static let maximum: CGFloat = 8

    static func next(after z: CGFloat) -> CGFloat {
        presets.first(where: { $0 > z + 0.001 }) ?? maximum
    }

    static func previous(before z: CGFloat) -> CGFloat {
        presets.last(where: { $0 < z - 0.001 }) ?? minimum
    }
}
