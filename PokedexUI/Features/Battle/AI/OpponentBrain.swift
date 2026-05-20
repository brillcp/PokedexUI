import Foundation

/// Wraps `BattleAIServiceProtocol` with a rolling move-history window.
@MainActor
final class OpponentBrain {
    private let service: BattleAIServiceProtocol
    private let historyLimit: Int
    private var history: [String] = []

    init(service: BattleAIServiceProtocol, historyLimit: Int = 4) {
        self.service = service
        self.historyLimit = historyLimit
    }

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
