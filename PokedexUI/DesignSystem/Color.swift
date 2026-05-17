import SwiftUI

extension Color {
    /// App background. Every full-screen feature (pokedex grid, search,
    /// opponent picker, loadout, battle) renders on this.
    static let darkGrey = Color(hex: "181818")
    /// Brand accent. Used for the bookmark heart, primary CTAs, legendary
    /// badges, and the VS chip.
    static let pokedexRed = Color(hex: "d53b47")
    /// Subtle white tint used by inline cards (fighter card, type matchup,
    /// opponent grid cell, loadout move cell unselected state). 5% over the
    /// `darkGrey` ground.
    static let cardBackground = Color.white.opacity(0.05)

    init?(hex: String, alpha: Double = 1.0) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString

        guard let hexNumber = UInt64(hexString, radix: 16), hexString.count == 6 else { return nil }

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255
        let b = Double(hexNumber & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }

    var isLight: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let brightness = (red * 299 + green * 587 + blue * 114) / 1000
            return brightness > 0.6
        }
        return false
    }
}

/// Standard radii used across the design system. Two tiers: chips for small
/// inline pills, cards for larger surfaces. Reaching for these instead of
/// inlining a magic number keeps the gameboy-style aesthetic uniform.
enum CornerRadius {
    /// Small inline pills: type tags, generation badges, effectiveness
    /// markers, status chips. The 4-point radius reads as "squared" next to
    /// the pixel font; capsules look too modern at chip size.
    static let chip: CGFloat = 4.0
    /// Larger containers: fighter cards, HP cards, move cells, type matchup
    /// blocks, the flavor-text bubble. Slightly more rounded than chips so
    /// the visual hierarchy reads at a glance.
    static let card: CGFloat = 4.0
}

extension RoundedRectangle {
    /// Standard chip shape (4-pt radius). Used by `Chip` itself and any
    /// inline pill smaller than a full card.
    static var chip: RoundedRectangle {
        RoundedRectangle(cornerRadius: CornerRadius.chip)
    }

    /// Standard card / glass-container shape (8-pt radius). Used by fighter
    /// cards, HP cards, move cells, and any larger surface.
    static var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: CornerRadius.card)
    }
}

extension UIColor {
    /// 6-character lowercase hex (no `#`), e.g. "ffcb05". Used to persist the
    /// dominant sprite color onto `Pokemon` so the next detail-view open
    /// renders its gradient background on frame 1.
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
