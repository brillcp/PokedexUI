import Foundation

/// Which side of the battle an event applies to.
enum BattleSide: Hashable, Sendable {
    case player
    case opponent

    var opposite: BattleSide { self == .player ? .opponent : .player }
}

/// Status ailments a combatant can have.
enum BattleStatus: String, Sendable {
    case none
    case paralysis
    case burn
    case poison
    case sleep

    var displayName: String {
        switch self {
        case .none: return ""
        case .paralysis: return "PAR"
        case .burn: return "BRN"
        case .poison: return "PSN"
        case .sleep: return "SLP"
        }
    }
}

/// Battle engine phase state machine.
enum BattlePhase: Sendable {
    case selectingMove
    case resolving
    case ended(winner: BattleSide?)
}

/// Discrete event emitted during a turn for sequential animation playback.
enum BattleEvent: Sendable {
    case used(BattleSide, moveName: String)
    case missed(BattleSide)
    case damaged(BattleSide, amount: Int, effectiveness: Double, crit: Bool)
    case statusApplied(BattleSide, BattleStatus)
    case statusTick(BattleSide, BattleStatus, amount: Int)
    case statChanged(BattleSide, stat: String, delta: Int)
    case healed(BattleSide, amount: Int)
    case recoil(BattleSide, amount: Int)
    case recharging(BattleSide)
    case wokeUp(BattleSide)
    case fastAsleep(BattleSide)
    case fullyParalyzed(BattleSide)
    case fainted(BattleSide)
    case ended(winner: BattleSide?)
}

/// One side of a fight with identity, stats, and mutable in-battle state.
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
    var sleepTurns: Int = 0
    var mustRecharge: Bool = false
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

    var effectiveSpeed: Int {
        status == .paralysis ? speed / 2 : speed
    }

    func stage(for stat: String) -> Int { statStages[stat] ?? 0 }

    mutating func applyStage(_ stat: String, delta: Int) {
        let next = max(-6, min(6, stage(for: stat) + delta))
        statStages[stat] = next
    }
}

func statStageMultiplier(_ stage: Int) -> Double {
    let s = max(-6, min(6, stage))
    return s >= 0 ? Double(2 + s) / 2.0 : 2.0 / Double(2 - s)
}

/// Snapshot of an in-flight battle.
struct BattleState: Sendable {
    var player: BattleCombatant
    var opponent: BattleCombatant
    var phase: BattlePhase = .selectingMove

    func combatant(for side: BattleSide) -> BattleCombatant {
        side == .player ? player : opponent
    }
}
