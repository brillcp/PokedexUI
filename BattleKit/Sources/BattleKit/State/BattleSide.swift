import Foundation

/// Which side of the battle an event applies to.
public enum BattleSide: Hashable, Sendable {
    case player
    case opponent

    public var opposite: BattleSide { self == .player ? .opponent : .player }
}
