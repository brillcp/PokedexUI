import BattleKit
import Foundation

/// On-device AI for battle decisions with deterministic fallbacks. The
/// concrete `BattleAIService` uses an LLM where available and falls back
/// to heuristics otherwise.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the best move for this turn. `defenderMoves` is the defender's
    /// full loadout; `defenderSeenMoves` is the subset already used in the
    /// current battle and is the only one shown to the LLM.
    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        defenderMoves: [MoveDetail],
        defenderSeenMoves: [String],
        typeChart: TypeChart,
        recentMoves: [String],
        turnNumber: Int
    ) async -> MoveDetail
    /// Pick an opponent id from the curated candidate pool.
    func chooseOpponent(
        player: OpponentCandidate,
        candidates: [OpponentCandidate],
        typeChart: TypeChart?
    ) async -> Int?
    /// Pick a 4-move loadout, informed by what the player chose.
    func chooseLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        playerMoves: [MoveDetail],
        typeChart: TypeChart
    ) async -> [MoveDetail]
}

/// Thin façade composing a `LanguageModelClient` with per-decision
/// strategy + prompt helpers. Each public method follows the same shape:
/// 1. Strategy produces a deterministic fallback.
/// 2. Client builds + parses an LLM prompt, falling back if unavailable.
/// 3. Strategy.adjust runs post-pick corrections against either branch.
actor BattleAIService {
    private let client = LanguageModelClient()
}

extension BattleAIService: BattleAIServiceProtocol {

    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        defenderMoves: [MoveDetail],
        defenderSeenMoves: [String],
        typeChart: TypeChart,
        recentMoves: [String],
        turnNumber: Int
    ) async -> MoveDetail {
        guard let first = moves.first else { return MoveDetail(name: "tackle") }
        let fallback = MoveStrategy.heuristicPick(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart, recentMoves: recentMoves
        ) ?? first
        let seen = defenderMoves.filter { defenderSeenMoves.contains($0.name) }
        let output = MovePrompt.build(
            attacker: attacker, defender: defender, moves: moves,
            defenderSeenMoves: seen, typeChart: typeChart, turnNumber: turnNumber
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
        player: OpponentCandidate,
        candidates: [OpponentCandidate],
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
        let shortlist = LoadoutStrategy.shortlist(
            fighter: fighter, opponent: opponent, moves: moves, typeChart: typeChart
        )
        let output = LoadoutPrompt.build(
            fighter: fighter, opponent: opponent, moves: shortlist, playerMoves: playerMoves, typeChart: typeChart
        )
        return await client.decide(
            fallback: fallback,
            prompt: output.prompt,
            temperature: 0.4,
            instructions: .loadout,
            parse: { raw in
                let parsed = LoadoutPrompt.parsePicks(raw: raw, indexMap: output.indexMap, moves: shortlist)
                guard !parsed.isEmpty else { return nil }
                return LoadoutStrategy.fill(
                    seed: parsed, fighter: fighter, opponent: opponent,
                    moves: shortlist, typeChart: typeChart, count: 4
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
