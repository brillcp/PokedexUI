import SwiftUI

/// Centralised type-to-color map for the design system.
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
