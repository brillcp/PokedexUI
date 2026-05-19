import Foundation

/// Stateful wrapper around `BattleAIServiceProtocol` that owns the rolling
/// move-history window the AI prompt uses to avoid repetitive play. Lets
/// `BattleViewModel` ask "what's the opponent's next move?" without
/// shuttling the history buffer + trim logic through its own properties.
@MainActor
final class OpponentBrain {
    private let service: BattleAIServiceProtocol
    private let historyLimit: Int
    private var history: [String] = []

    init(service: BattleAIServiceProtocol, historyLimit: Int = 4) {
        self.service = service
        self.historyLimit = historyLimit
    }

    /// Resolve the opponent's next move and append it to the rolling
    /// history window. Falls back to the underlying service's behavior on
    /// AI unavailability (random pick), so the returned move is always
    /// legal.
    func nextMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> MoveDetail {
        let move = await service.chooseMove(
            attacker:    attacker,
            defender:    defender,
            moves:       moves,
            typeChart:   typeChart,
            recentMoves: history
        )
        history.append(move.name)
        if history.count > historyLimit {
            history.removeFirst()
        }
        return move
    }
}
