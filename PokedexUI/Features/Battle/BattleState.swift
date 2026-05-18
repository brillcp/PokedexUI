import Foundation

/// Which combatant a battle event applies to. The opposite side is the
/// natural target for damage, status, and stat-change events.
enum BattleSide: Hashable, Sendable {
    case player
    case opponent

    var opposite: BattleSide { self == .player ? .opponent : .player }
}

/// MVP status ailment set: paralysis, burn, poison. Sleep/freeze/confusion
/// are deliberately deferred. `displayName` is the 3-letter badge shown on
/// the HP card.
enum BattleStatus: String, Sendable {
    case none
    case paralysis
    case burn
    case poison

    var displayName: String {
        switch self {
        case .none: return ""
        case .paralysis: return "PAR"
        case .burn: return "BRN"
        case .poison: return "PSN"
        }
    }
}

/// Engine state machine. Transitions: `.selectingMove → .resolving → .ended`
/// (or back to `.selectingMove` for the next round). Drives whether the move
/// grid accepts taps.
enum BattlePhase: Sendable {
    case selectingMove
    case resolving
    case ended(winner: BattleSide?)
}

/// One thing that happens during a turn. The view consumes events sequentially
/// and animates each one (damage tween, status flash, faint, etc.).
enum BattleEvent: Sendable {
    case used(BattleSide, moveName: String)
    case missed(BattleSide)
    case damaged(BattleSide, amount: Int, effectiveness: Double, crit: Bool)
    case statusApplied(BattleSide, BattleStatus)
    case statusTick(BattleSide, BattleStatus, amount: Int)
    case statChanged(BattleSide, stat: String, delta: Int)
    case fullyParalyzed(BattleSide)
    case fainted(BattleSide)
    case ended(winner: BattleSide?)
}

/// One side of a fight: identity + stats + mutable in-battle state (current
/// HP, status ailment, stat stages). Built from a `PokemonViewModel` plus a
/// chosen movepool; the engine mutates `currentHP`, `status`, and
/// `statStages` as the round resolves.
struct BattleCombatant: Sendable {
    let id: Int
    let name: String
    let frontSpriteURL: String
    let backSpriteURL: String?
    let typeNames: [String]
    let maxHP: Int
    let attack: Int
    let defense: Int
    let specialAttack: Int
    let specialDefense: Int
    let speed: Int
    var currentHP: Int
    var status: BattleStatus
    var statStages: [String: Int]
    let moves: [MoveDetail]

    init(pokemon: PokemonViewModel, moves: [MoveDetail]) {
        let stats = pokemon.statLookup
        let baseHP = stats["hp"] ?? 50
        self.id = pokemon.id
        self.name = pokemon.name
        self.frontSpriteURL = pokemon.frontSprite
        self.backSpriteURL = pokemon.backSprite
        self.typeNames = pokemon.typeNames
        self.maxHP = baseHP * 2 + 60  // rough level-50 HP scaling
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

    var isFainted: Bool { currentHP <= 0 }

    /// Speed accounting for paralysis halving.
    var effectiveSpeed: Int {
        status == .paralysis ? speed / 2 : speed
    }

    func stage(for stat: String) -> Int { statStages[stat] ?? 0 }

    mutating func applyStage(_ stat: String, delta: Int) {
        let next = max(-6, min(6, stage(for: stat) + delta))
        statStages[stat] = next
    }
}

/// Standard Pokémon stat-stage multiplier: ±1 ≈ 1.5×, ±2 = 2×, capped at ±6.
func statStageMultiplier(_ stage: Int) -> Double {
    let s = max(-6, min(6, stage))
    return s >= 0 ? Double(2 + s) / 2.0 : 2.0 / Double(2 - s)
}

/// Snapshot of an in-flight battle. `BattleEngine` owns the canonical state;
/// `BattleViewModel` keeps a `state` copy that mutates one event at a time so
/// SwiftUI animates each step in sequence rather than jumping to the final
/// frame.
struct BattleState: Sendable {
    var player: BattleCombatant
    var opponent: BattleCombatant
    var phase: BattlePhase = .selectingMove

    func combatant(for side: BattleSide) -> BattleCombatant {
        side == .player ? player : opponent
    }
}
