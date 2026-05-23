import PokeBattleKit
import FoundationModels

/// Debug-only AI logging. Compiles to nothing in release builds.
@inline(__always)
func aiLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[AI] \(message())")
    #endif
}

private func hpPct(_ c: Combatant) -> Int {
    Int(Double(c.currentHP) / Double(max(1, c.maxHP)) * 100)
}

/// On-device AI for battle decisions with deterministic fallbacks. The
/// concrete `BattleAIService` uses an LLM where available and falls back
/// to heuristics otherwise.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the best move for this turn. `defenderMoves` is the defender's
    /// full loadout; `defenderSeenMoves` is the subset already used in the
    /// current battle and is the only one shown to the LLM.
    func chooseMove(
        attacker: Combatant,
        defender: Combatant,
        moves: [Move],
        defenderMoves: [Move],
        defenderSeenMoves: [String],
        typeChart: TypeChart,
        recentMoves: [String],
        turnNumber: Int
    ) async -> Move
    /// Pick an opponent id from the curated candidate pool.
    func chooseOpponent(
        player: Candidate,
        candidates: [Candidate],
        typeChart: TypeChart?
    ) async -> Int?
    /// Pick a 4-move loadout, informed by what the player chose.
    func chooseLoadout(
        for fighter: Combatant,
        against opponent: Combatant,
        moves: [Move],
        playerMoves: [Move],
        typeChart: TypeChart
    ) async -> [Move]
}

/// Thin facade composing a `LanguageModelClient` with per-decision
/// strategy + prompt helpers. Each public method follows the same shape:
/// 1. Strategy produces a deterministic fallback.
/// 2. Structured generation with tools attempts a smarter pick.
/// 3. Strategy.adjust runs post-pick corrections against either branch.
actor BattleAIService {
    private let client = LanguageModelClient()
}

extension BattleAIService: BattleAIServiceProtocol {

    func chooseMove(
        attacker: Combatant,
        defender: Combatant,
        moves: [Move],
        defenderMoves: [Move],
        defenderSeenMoves: [String],
        typeChart: TypeChart,
        recentMoves: [String],
        turnNumber: Int
    ) async -> Move {
        aiLog("--- MOVE PICK (turn \(turnNumber)) ---")
        aiLog("\(attacker.name) \(hpPct(attacker))% vs \(defender.name) \(hpPct(defender))%")
        aiLog("Loadout: \(moves.map(\.name).joined(separator: ", "))")
        aiLog("Recent: \(recentMoves.joined(separator: ", "))")
        let scores = moves.map { m in
            let s = MoveScoring.inBattleScore(move: m, attacker: attacker, defender: defender, typeChart: typeChart, recentMoves: recentMoves)
            return "\(m.name)=\(String(format: "%.1f", s))"
        }
        aiLog("Scores: \(scores.joined(separator: ", "))")

        guard let first = moves.first else { return PokeBattleKit.move(named: "tackle")! }
        let fallback = MoveStrategy.heuristicPick(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart, recentMoves: recentMoves
        ) ?? first
        aiLog("Heuristic fallback: \(fallback.name)")

        let movesByName = Dictionary(moves.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        let tools: [any Tool] = [
            CheckTypeTool(typeChart: typeChart),
            EstimateDamageTool(attacker: attacker, defender: defender, typeChart: typeChart, movesByName: movesByName)
        ]

        let seen = defenderSeenMoves.isEmpty ? "" : "\nDefender used: \(defenderSeenMoves.joined(separator: ", "))"
        let moveList = moves.map { describeMove($0) }.joined(separator: "\n")
        let prompt = """
        \(BattleContext.compact(attacker: attacker, defender: defender, turnNumber: turnNumber))\(seen)

        Available moves:
        \(moveList)

        \(BattleContext.tacticalHint(attacker: attacker, defender: defender, moves: moves))
        """

        let pick = await client.decide(
            fallback: fallback,
            prompt: prompt,
            generating: MovePickResult.self,
            tools: tools,
            temperature: 0.35,
            instructions: .move,
            resolve: { result in
                aiLog("LLM chose: \(result.moveName)")
                return movesByName[result.moveName]
            },
            adjust: {
                let adjusted = MoveStrategy.adjust(
                    pick: $0, attacker: attacker, defender: defender,
                    moves: moves, typeChart: typeChart, fallback: fallback
                )
                if adjusted.name != $0.name { aiLog("Adjust: \($0.name) -> \(adjusted.name)") }
                return adjusted
            }
        )
        aiLog("FINAL PICK: \(pick.name)")
        return pick
    }

    func chooseOpponent(
        player: Candidate,
        candidates: [Candidate],
        typeChart: TypeChart?
    ) async -> Int? {
        let pool = candidates.filter { $0.id != player.id }
        guard !pool.isEmpty else { return nil }
        aiLog("--- OPPONENT PICK ---")
        aiLog("Player: \(player.name) (\(player.typeNames.joined(separator: "/")), BST \(player.baseStatTotal))")
        aiLog("Pool size: \(pool.count)")
        let fallback = OpponentStrategy.heuristicPick(player: player, candidates: pool, typeChart: typeChart)
        if let fbId = fallback, let fb = pool.first(where: { $0.id == fbId }) {
            aiLog("Heuristic fallback: \(fb.name) (BST \(fb.baseStatTotal))")
        }
        let output = OpponentPrompt.build(player: player, candidates: pool, typeChart: typeChart)

        let pick = await client.decide(
            fallback: fallback,
            prompt: output.prompt,
            generating: OpponentPickResult.self,
            tools: [],
            temperature: 0.3,
            instructions: .opponent,
            resolve: { OpponentPrompt.parsePick(raw: String($0.index), indexMap: output.indexMap) },
            adjust: { $0 }
        )
        if let id = pick, let chosen = pool.first(where: { $0.id == id }) {
            aiLog("FINAL OPPONENT: \(chosen.name) (\(chosen.typeNames.joined(separator: "/")), BST \(chosen.baseStatTotal))")
        }
        return pick
    }

    func chooseLoadout(
        for fighter: Combatant,
        against opponent: Combatant,
        moves: [Move],
        playerMoves: [Move],
        typeChart: TypeChart
    ) async -> [Move] {
        aiLog("--- LOADOUT PICK ---")
        aiLog("\(fighter.name) (\(fighter.typeNames.joined(separator: "/"))) vs \(opponent.name) (\(opponent.typeNames.joined(separator: "/")))")
        aiLog("Move pool: \(moves.count) moves")
        aiLog("Player chose: \(playerMoves.map(\.name).joined(separator: ", "))")
        guard moves.count > 4 else { return moves }
        let fallback = LoadoutStrategy.heuristicPick(
            fighter: fighter, opponent: opponent, moves: moves, typeChart: typeChart
        )
        aiLog("Heuristic fallback: \(fallback.map(\.name).joined(separator: ", "))")
        let shortlist = LoadoutStrategy.shortlist(
            fighter: fighter, opponent: opponent, moves: moves, typeChart: typeChart
        )
        aiLog("Shortlist: \(shortlist.count) moves")

        let movesByName = Dictionary(shortlist.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        let tools: [any Tool] = [
            CheckTypeTool(typeChart: typeChart),
            EstimateDamageTool(attacker: fighter, defender: opponent, typeChart: typeChart, movesByName: movesByName)
        ]

        let moveList = shortlist.map { describeMove($0) }.joined(separator: "\n")
        let prompt = """
        Pick 4 moves for \(fighter.name) (\(fighter.typeNames.joined(separator: "/"))) vs \(opponent.name) (\(opponent.typeNames.joined(separator: "/"))).

        Available moves:
        \(moveList)

        Pick a balanced loadout: damage moves with good type coverage, plus utility (status, boosts).
        """

        let picks = await client.decide(
            fallback: fallback,
            prompt: prompt,
            generating: LoadoutPickResult.self,
            tools: tools,
            temperature: 0.4,
            instructions: .loadout,
            resolve: { result in
                let parsed = result.moveNames.compactMap { movesByName[$0] }
                aiLog("LLM parsed: \(parsed.map(\.name).joined(separator: ", "))")
                guard !parsed.isEmpty else { return nil }
                let filled = LoadoutStrategy.fill(
                    seed: parsed, fighter: fighter, opponent: opponent,
                    moves: shortlist, typeChart: typeChart, count: 4
                )
                if filled.count > parsed.count {
                    aiLog("Filled to 4: \(filled.map(\.name).joined(separator: ", "))")
                }
                return filled
            },
            adjust: {
                let adjusted = LoadoutStrategy.adjust(
                    picks: $0, pool: moves, fighter: fighter, opponent: opponent, typeChart: typeChart
                )
                if adjusted.map(\.name) != $0.map(\.name) {
                    aiLog("Adjust: \($0.map(\.name).joined(separator: ", ")) -> \(adjusted.map(\.name).joined(separator: ", "))")
                }
                return adjusted
            }
        )
        aiLog("FINAL LOADOUT: \(picks.map(\.name).joined(separator: ", "))")
        return picks
    }
}
