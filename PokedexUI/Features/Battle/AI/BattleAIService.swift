import Foundation
import FoundationModels

/// On-device AI for the battle screen: picks moves, opponents, and loadouts.
///
/// Each call gets a fresh `LanguageModelSession` to avoid context-window
/// overflow and session-state corruption across turns.
///
/// `.permissiveContentTransformations` guardrails are required because Pokemon
/// move/status names ("hyper-beam", "burn", "poison") false-positive the
/// default safety classifier. This is string-only generation; guided
/// generation (@Generable) re-enables default guardrails and would break this.
///
/// Every call degrades gracefully to a deterministic fallback if Apple
/// Intelligence is unavailable or generation fails.
protocol BattleAIServiceProtocol: Sendable {
    func chooseMove(attacker: BattleCombatant, defender: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart, recentMoves: [String]) async -> MoveDetail
    /// Pick an opponent id from the supplied candidate snapshots. The caller
    /// maps the returned id back to a SwiftData `Pokemon` on the main actor.
    /// Returns `nil` when the model is unavailable or can't decide; callers
    /// should fall back to a random pick.
    func chooseOpponent(player: PokemonAISnapshot, candidates: [PokemonAISnapshot]) async -> Int?
    func chooseLoadout(for fighter: BattleCombatant, against opponent: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart) async -> [MoveDetail]
}

actor BattleAIService: BattleAIServiceProtocol {
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private let prompts = BattleAIPromptBuilder()

    // MARK: - BattleAIServiceProtocol

    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String]
    ) async -> MoveDetail {
        guard let first = moves.first else { return MoveDetail(name: "tackle") }
        guard isAvailable else { return moves.randomElement() ?? first }
        let effectiveness = moves.map { typeChart.multiplier(attacking: $0.typeName, defenders: defender.typeNames) }
        let (prompt, indexMap) = prompts.buildMovePrompt(attacker: attacker, defender: defender, moves: moves, effectiveness: effectiveness, recentMoves: recentMoves)
        print("[llm] chooseMove: \(attacker.name) vs \(defender.name), moves: \(moves.map(\.name)), recent: \(recentMoves)")
        do {
            let raw = try await moveSession().respond(to: prompt, options: .init(temperature: 0.35)).content
            print("[llm] chooseMove: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let shuffledIdx = BattleAIResponseParser.firstInt(in: raw),
               let originalIdx = indexMap[shuffledIdx],
               moves.indices.contains(originalIdx) {
                print("[llm] chooseMove: shuffled \(shuffledIdx) -> original \(originalIdx) (\(moves[originalIdx].name))")
                return moves[originalIdx]
            }
        } catch { print("[llm error] chooseMove: \(error)") }
        return moves.randomElement() ?? first
    }

    func chooseOpponent(
        player: PokemonAISnapshot,
        candidates: [PokemonAISnapshot]
    ) async -> Int? {
        let pool = candidates.filter { $0.id != player.id }
        guard !pool.isEmpty else { return nil }
        guard isAvailable else { return pool.randomElement()?.id }
        let prompt = prompts.buildOpponentPrompt(player: player, candidates: pool)
        print("[llm] chooseOpponent: for \(player.name) (\(player.typeNames.joined(separator: "/"))) from \(pool.count) candidates")
        do {
            let raw = try await opponentSession().respond(to: prompt, options: .init(temperature: 0.5)).content
            print("[llm] chooseOpponent: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let id = BattleAIResponseParser.firstInt(in: raw), pool.contains(where: { $0.id == id }) {
                print("[llm] chooseOpponent: resolved to id \(id)")
                return id
            }
        } catch { print("[llm error] chooseOpponent: \(error)") }
        return pool.randomElement()?.id
    }

    func chooseLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> [MoveDetail] {
        let size = 4
        let fallback = BattleAIResponseParser.heuristicLoadout(from: moves, count: size)
        guard moves.count > size else { return moves }
        guard isAvailable else { return fallback }
        let effectiveness = moves.map { typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) }
        let prompt = prompts.buildLoadoutPrompt(fighter: fighter, opponent: opponent, moves: moves, effectiveness: effectiveness, loadoutSize: size)
        print("[llm] chooseLoadout: \(fighter.name) vs \(opponent.name), pool size \(moves.count)")
        do {
            let raw = try await loadoutSession().respond(to: prompt, options: .init(temperature: 0.4)).content
            print("[llm] chooseLoadout: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            let indices = BattleAIResponseParser.intsOnLastLine(of: raw)
            print("[llm] chooseLoadout: parsed indices \(indices)")
            let result = BattleAIResponseParser.assembleLoadout(indices: indices, from: moves, size: size)
            print("[llm] chooseLoadout: final loadout: \(result.map(\.name))")
            return result
        } catch { print("[llm error] chooseLoadout: \(error)") }
        return fallback
    }

}

// MARK: - Private

private extension BattleAIService {
    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    func moveSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.moveInstructions)
    }

    func loadoutSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.loadoutInstructions)
    }

    func opponentSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.opponentInstructions)
    }

    static let moveInstructions: String = loadInstructions("BattleAIMoveInstructions", fallback: "You are an expert Pokemon battler.")
    static let loadoutInstructions: String = loadInstructions("BattleAILoadoutInstructions", fallback: "You are an expert Pokemon teambuilder.")
    static let opponentInstructions: String = loadInstructions("BattleAIOpponentInstructions", fallback: "You are a Pokemon battle matchmaker.")

    static func loadInstructions(_ name: String, fallback: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return fallback }
        return text
    }
}
