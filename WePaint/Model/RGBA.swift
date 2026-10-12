import SwiftUI
import UIKit

/// 8-bit sRGB color with straight (non-premultiplied) alpha.
struct RGBA: Equatable, Hashable, Codable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8 = 255

    static let black = RGBA(r: 0, g: 0, b: 0)
    static let white = RGBA(r: 255, g: 255, b: 255)
    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        a = 255
    }

    init(_ uiColor: UIColor) {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        if !uiColor.getRed(&fr, green: &fg, blue: &fb, alpha: &fa) {
            var w: CGFloat = 0
            uiColor.getWhite(&w, alpha: &fa)
            fr = w; fg = w; fb = w
        }
        func q(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        r = q(fr); g = q(fg); b = q(fb); a = q(fa)
    }

    init(_ color: Color) {
        self.init(UIColor(color))
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    var cgColor: CGColor { uiColor.cgColor }
    var color: Color { Color(uiColor) }

    var isDark: Bool {
        (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) < 128
    }

    var hexString: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// Squared distance in RGBA space, used for fill tolerance.
    func distance(to other: RGBA) -> Int {
        let dr = Int(r) - Int(other.r)
        let dg = Int(g) - Int(other.g)
        let db = Int(b) - Int(other.b)
        let da = Int(a) - Int(other.a)
        return dr * dr + dg * dg + db * db + da * da
    }

    /// Value as premultiplied bytes in memory order R,G,B,A.
    var premultipliedBytes: (UInt8, UInt8, UInt8, UInt8) {
        if a == 255 { return (r, g, b, a) }
        let af = Int(a)
        return (UInt8((Int(r) * af + 127) / 255), UInt8((Int(g) * af + 127) / 255), UInt8((Int(b) * af + 127) / 255), a)
    }

    static func fromPremultiplied(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> RGBA {
        if a == 255 || a == 0 { return RGBA(r: r, g: g, b: b, a: a) }
        let af = Int(a)
        func un(_ v: UInt8) -> UInt8 { UInt8(min(255, (Int(v) * 255 + af / 2) / af)) }
        return RGBA(r: un(r), g: un(g), b: un(b), a: a)
    }
}

/// The default Windows 11 Paint palette (two rows of ten).
enum PaintPalette {
    static let defaultColors: [RGBA] = [
        RGBA(hex: 0x000000), RGBA(hex: 0x7F7F7F), RGBA(hex: 0x880015), RGBA(hex: 0xED1C24), RGBA(hex: 0xFF7F27),
        RGBA(hex: 0xFFF200), RGBA(hex: 0x22B14C), RGBA(hex: 0x00A2E8), RGBA(hex: 0x3F48CC), RGBA(hex: 0xA349A4),
        RGBA(hex: 0xFFFFFF), RGBA(hex: 0xC3C3C3), RGBA(hex: 0xB97A57), RGBA(hex: 0xFFAEC9), RGBA(hex: 0xFFC90E),
        RGBA(hex: 0xEFE4B0), RGBA(hex: 0xB5E61D), RGBA(hex: 0x99D9EA), RGBA(hex: 0x7092BE), RGBA(hex: 0xC8BFE7),
    ]
}
