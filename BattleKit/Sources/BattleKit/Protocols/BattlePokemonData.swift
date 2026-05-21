import Foundation

/// Minimal Pokemon data the battle engine needs to build a combatant.
public protocol BattlePokemonData: Sendable {
    var id: Int { get }
    var name: String { get }
    var frontSprite: String { get }
    var backSprite: String? { get }
    var typeNames: [String] { get }
    /// Base stats keyed by canonical name ("hp", "attack", "defense",
    /// "special-attack", "special-defense", "speed").
    var statLookup: [String: Int] { get }
}
