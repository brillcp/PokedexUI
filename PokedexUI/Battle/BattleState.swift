import Foundation

enum BattleSide: Hashable, Sendable {
    case player
    case opponent

    var opposite: BattleSide { self == .player ? .opponent : .player }
}

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
    case fullyParalyzed(BattleSide)
    case fainted(BattleSide)
    case ended(winner: BattleSide?)
}

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
    let moves: [MoveDetail]

    init(pokemon: PokemonViewModelProtocol, moves: [MoveDetail]) {
        let stats = Dictionary(uniqueKeysWithValues: pokemon.stats.map { ($0.stat.name, $0.baseStat) })
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
        self.moves = moves
    }

    var isFainted: Bool { currentHP <= 0 }

    /// Speed accounting for paralysis halving.
    var effectiveSpeed: Int {
        status == .paralysis ? speed / 2 : speed
    }
}

struct BattleState: Sendable {
    var player: BattleCombatant
    var opponent: BattleCombatant
    var phase: BattlePhase = .selectingMove

    func combatant(for side: BattleSide) -> BattleCombatant {
        side == .player ? player : opponent
    }
}
