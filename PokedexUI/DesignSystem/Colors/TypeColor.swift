import SwiftUI

/// Centralised type → color map used by both the battle move grid and the
/// loadout move picker. Lives in the design system so any future surface
/// (weakness chart, type filter) draws from the same palette.
enum TypeColor {
    static func color(for name: String) -> Color {
        switch name {
        case "fire":                       return .orange
        case "water":                      return .blue
        case "grass":                      return .green
        case "electric":                   return .yellow
        case "psychic":                    return .pink
        case "ice":                        return .cyan
        case "fighting", "rock", "ground": return .brown
        case "poison", "ghost":            return .purple
        case "flying", "fairy":            return .mint
        case "bug":                        return .green.opacity(0.7)
        case "steel":                      return .gray
        case "dark":                       return .black
        case "dragon":                     return .indigo
        default:                           return .gray
        }
    }
}
