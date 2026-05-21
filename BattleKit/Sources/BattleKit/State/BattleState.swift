import Foundation

/// Snapshot of an in-flight battle.
public struct BattleState: Sendable {
    public var player: BattleCombatant
    public var opponent: BattleCombatant
    public var phase: BattlePhase = .selectingMove

    public init(player: BattleCombatant, opponent: BattleCombatant) {
        self.player = player
        self.opponent = opponent
    }

    public func combatant(for side: BattleSide) -> BattleCombatant {
        side == .player ? player : opponent
    }
}
