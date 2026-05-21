import Foundation

/// One side of a fight with identity, stats, and mutable in-battle state.
public struct BattleCombatant: Sendable {
    public let id: Int
    public let name: String
    public let frontSpriteURL: String
    public let backSpriteURL: String?
    public let typeNames: [String]
    public let maxHP: Int
    public let attack: Int
    public let defense: Int
    public let specialAttack: Int
    public let specialDefense: Int
    public let speed: Int
    public var currentHP: Int
    public var status: BattleStatus
    public var sleepTurns: Int = 0
    public var mustRecharge: Bool = false
    public var statStages: [String: Int]
    public let moves: [BattleMoveSnapshot]

    public init(
        pokemon: some BattlePokemonData,
        moves: [BattleMoveSnapshot],
        hpBonus: Double = 1.0
    ) {
        let stats = pokemon.statLookup
        let baseHP = stats["hp"] ?? 50
        self.id = pokemon.id
        self.name = pokemon.name
        self.frontSpriteURL = pokemon.frontSprite
        self.backSpriteURL = pokemon.backSprite
        self.typeNames = pokemon.typeNames
        self.maxHP = Int(Double(baseHP * 2 + 110) * hpBonus)
        self.currentHP = self.maxHP
        self.attack = stats["attack"] ?? 50
        self.defense = stats["defense"] ?? 50
        self.specialAttack = stats["special-attack"] ?? 50
        self.specialDefense = stats["special-defense"] ?? 50
        self.speed = stats["speed"] ?? 50
        self.status = .none
        self.statStages = [:]
        self.moves = moves
    }

    public var isFainted: Bool { currentHP <= 0 }
    public var isBoosted: Bool { statStages.values.contains { $0 > 0 } }

    public var effectiveSpeed: Int {
        status == .paralysis ? speed / 2 : speed
    }

    public func stage(for stat: String) -> Int { statStages[stat] ?? 0 }

    public mutating func applyStage(_ stat: String, delta: Int) {
        let next = max(-6, min(6, stage(for: stat) + delta))
        statStages[stat] = next
    }
}
