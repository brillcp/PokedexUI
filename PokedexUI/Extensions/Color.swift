import SwiftUI

extension Color {
    static let darkGrey = Color(hex: "222222")
    static let pokedexRed = Color(hex: "d53b47")
    static let orange = Color(hex: "f89e2e")
    static let blue = Color(hex: "3898fe")
    static let grey = Color(hex: "8db6d2")
    static let green = Color(hex: "5ba74f")

    init?(hex: String, alpha: Double = 1.0) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString

        guard let hexNumber = UInt64(hexString, radix: 16), hexString.count == 6 else { return nil }

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255
        let b = Double(hexNumber & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: -
extension Color {
    var isLight: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let brightness = (red * 299 + green * 587 + blue * 114) / 1000
            return brightness > 0.7
        }
        return false
    }
}
