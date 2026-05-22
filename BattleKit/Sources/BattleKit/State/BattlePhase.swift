import Foundation

/// Battle engine phase state machine. Driven by `BattleEngine`; not part
/// of the public surface.
enum BattlePhase: Sendable {
    case selectingMove
    case resolving
    case ended(winner: BattleSide?)
}
