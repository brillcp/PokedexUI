import Foundation

/// Battle engine phase state machine.
public enum BattlePhase: Sendable {
    case selectingMove
    case resolving
    case ended(winner: BattleSide?)
}
