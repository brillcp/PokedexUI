import BattleKit
import Foundation

/// On-device AI for battle decisions with deterministic fallbacks.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the best move for this turn.
    func chooseMove(attacker: BattleCombatant, defender: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart, recentMoves: [String], turnNumber: Int) async -> MoveDetail
    /// Pick an opponent id from candidate snapshots.
    func chooseOpponent(player: OpponentCandidateSnapshot, candidates: [OpponentCandidateSnapshot], typeChart: TypeChart?) async -> Int?
    /// Pick a 4-move loadout for a 1v1 battle, informed by what the player chose.
    func chooseLoadout(for fighter: BattleCombatant, against opponent: BattleCombatant, moves: [MoveDetail], playerMoves: [MoveDetail], typeChart: TypeChart) async -> [MoveDetail]
}

/// Thin façade over ``LanguageModelClient`` plus per-decision strategy
/// and prompt helpers. Each public method composes:
///   `Strategy.heuristicPick` → fallback used when the LLM is unavailable
///   or returns nothing usable.
///   `Prompt.build` / `Prompt.parsePick` → LLM I/O.
///   `Strategy.adjust` → post-pick correction pipeline run against either
///   branch.
/// `LanguageModelClient.decide(...)` ties the three together.
actor BattleAIService {
    private let client = LanguageModelClient()
}

// MARK: - BattleAIServiceProtocol
extension BattleAIService: BattleAIServiceProtocol {

    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String],
        turnNumber: Int
    ) async -> MoveDetail {
        guard let first = moves.first else { return MoveDetail(name: "tackle") }
        let fallback = MoveStrategy.heuristicPick(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart, recentMoves: recentMoves
        ) ?? first
        let output = MovePrompt.build(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart, turnNumber: turnNumber
        )
        return await client.decide(
            fallback: fallback,
            prompt: output.prompt,
            temperature: 0.35,
            instructions: .move,
            parse: { MovePrompt.parsePick(raw: $0, indexMap: output.indexMap, moves: moves) },
            adjust: {
                MoveStrategy.adjust(
                    pick: $0, attacker: attacker, defender: defender,
                    moves: moves, typeChart: typeChart, fallback: fallback
                )
            }
        )
    }

    func chooseOpponent(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) async -> Int? {
        let pool = candidates.filter { $0.id != player.id }
        guard !pool.isEmpty else { return nil }
        let fallback = OpponentStrategy.heuristicPick(player: player, candidates: pool, typeChart: typeChart)
        let output = OpponentPrompt.build(player: player, candidates: pool, typeChart: typeChart)
        return await client.decide(
            fallback: fallback,
            prompt: output.prompt,
            temperature: 0.3,
            instructions: .opponent,
            parse: { OpponentPrompt.parsePick(raw: $0, indexMap: output.indexMap) },
            adjust: { $0 }
        )
    }

    func chooseLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        playerMoves: [MoveDetail],
        typeChart: TypeChart
    ) async -> [MoveDetail] {
        guard moves.count > 4 else { return moves }
        let fallback = LoadoutStrategy.heuristicPick(
            fighter: fighter, opponent: opponent, moves: moves, typeChart: typeChart
        )
        let shortMoves = LoadoutStrategy.shortlist(
            fighter: fighter, opponent: opponent, moves: moves, typeChart: typeChart
        )
        let output = LoadoutPrompt.build(
            fighter: fighter, opponent: opponent, moves: shortMoves, playerMoves: playerMoves, typeChart: typeChart
        )
        return await client.decide(
            fallback: fallback,
            prompt: output.prompt,
            temperature: 0.4,
            instructions: .loadout,
            parse: { raw in
                let parsed = LoadoutPrompt.parsePicks(raw: raw, indexMap: output.indexMap, moves: shortMoves)
                guard !parsed.isEmpty else { return nil }
                return LoadoutStrategy.fill(
                    seed: parsed, fighter: fighter, opponent: opponent,
                    moves: shortMoves, typeChart: typeChart, count: 4
                )
            },
            adjust: {
                LoadoutStrategy.adjust(
                    picks: $0, pool: moves, fighter: fighter, opponent: opponent, typeChart: typeChart
                )
            }
        )
    }
}
