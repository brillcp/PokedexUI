import Foundation

/// Status ailments a combatant can have.
public enum BattleStatus: String, Sendable {
    case none
    case paralysis
    case burn
    case poison
    case sleep

    public var displayName: String {
        switch self {
        case .none: return ""
        case .paralysis: return "PAR"
        case .burn: return "BRN"
        case .poison: return "PSN"
        case .sleep: return "SLP"
        }
    }

    public var label: String {
        switch self {
        case .none: return "healthy"
        case .paralysis: return "paralyzed"
        case .burn: return "burned"
        case .poison: return "poisoned"
        case .sleep: return "asleep"
        }
    }

    public init(ailment: String) {
        switch ailment {
        case "paralysis": self = .paralysis
        case "burn": self = .burn
        case "poison", "bad-poison": self = .poison
        case "sleep": self = .sleep
        default: self = .none
        }
    }
}
