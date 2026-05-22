import BattleKit
import Foundation

/// Per-battle wrapper around `BattleAIServiceProtocol` that tracks the
/// opponent's recent picks (for recency penalty) and which player moves
/// have been observed (so the next AI prompt only sees scouted threats).
@MainActor
final class BattleAIDriver {
    private let service: BattleAIServiceProtocol
    private let historyLimit: Int
    private var history: [String] = []
    private var turnNumber: Int = 0
    private(set) var playerSeenMoves: Set<String> = []

    init(service: BattleAIServiceProtocol, historyLimit: Int = 4) {
        self.service = service
        self.historyLimit = historyLimit
    }

    /// Ask the service for the AI's next move. Updates the rolling
    /// recent-moves window on its way out.
    func nextOpponentMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        opponentMoves: [MoveDetail],
        playerMoves: [MoveDetail],
        typeChart: TypeChart
    ) async -> MoveDetail {
        turnNumber += 1
        let pick = await service.chooseMove(
            attacker:          attacker,
            defender:          defender,
            moves:             opponentMoves,
            defenderMoves:     playerMoves,
            defenderSeenMoves: Array(playerSeenMoves),
            typeChart:         typeChart,
            recentMoves:       history,
            turnNumber:        turnNumber
        )
        history.append(pick.name)
        if history.count > historyLimit { history.removeFirst() }
        return pick
    }

    /// Add `name` to the seen set if `events` show the player actually
    /// used a move this turn (i.e. wasn't fully paralyzed or asleep).
    func recordPlayerUsed(_ name: String, in events: [BattleEvent]) {
        let acted = events.contains { event in
            if case .used(.player, _) = event { return true }
            return false
        }
        if acted { playerSeenMoves.insert(name) }
    }
}
