import Foundation

/// Provides type-effectiveness multipliers for damage calculation.
public protocol TypeEffectivenessProviding: Sendable {
    /// Combined multiplier for `attacking` type against all `defenders` types.
    func multiplier(attacking: String, defenders: [String]) -> Double
}
