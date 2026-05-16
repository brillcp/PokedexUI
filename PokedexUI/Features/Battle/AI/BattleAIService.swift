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
    func chooseMove(attacker: BattleCombatant, defender: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart) async -> MoveDetail
    func chooseOpponent(for player: PokemonSummary, playerTypes: [String], candidates: [PokemonSummary]) async -> PokemonSummary
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
        typeChart: TypeChart
    ) async -> MoveDetail {
        guard let first = moves.first else { return MoveDetail(name: "tackle") }
        guard isAvailable else { return moves.randomElement() ?? first }
        let effectiveness = moves.map { typeChart.multiplier(attacking: $0.typeName, defenders: defender.typeNames) }
        let prompt = prompts.buildMovePrompt(attacker: attacker, defender: defender, moves: moves, effectiveness: effectiveness)
        print("[llm] chooseMove: \(attacker.name) vs \(defender.name), moves: \(moves.map(\.name))")
        do {
            let raw = try await session().respond(to: prompt, options: .init(temperature: 0.2)).content
            print("[llm] chooseMove: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let i = BattleAIResponseParser.firstInt(in: raw), moves.indices.contains(i) {
                print("[llm] chooseMove: resolved to \(moves[i].name)")
                return moves[i]
            }
        } catch { print("[llm error] chooseMove: \(error)") }
        return moves.randomElement() ?? first
    }

    func chooseOpponent(
        for player: PokemonSummary,
        playerTypes: [String],
        candidates: [PokemonSummary]
    ) async -> PokemonSummary {
        let pool = candidates.filter { $0.id != player.id }
        guard let fallback = pool.randomElement() else { return player }
        guard isAvailable else { return fallback }
        let prompt = prompts.buildOpponentPrompt(player: player, playerTypes: playerTypes, candidates: pool)
        print("[llm] chooseOpponent: for \(player.name) (\(playerTypes.joined(separator: "/"))) from \(pool.count) candidates")
        do {
            let raw = try await session().respond(to: prompt, options: .init(temperature: 0.5)).content
            print("[llm] chooseOpponent: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let id = BattleAIResponseParser.firstInt(in: raw), let picked = pool.first(where: { $0.id == id }) {
                print("[llm] chooseOpponent: resolved to \(picked.name)")
                return picked
            }
        } catch { print("[llm error] chooseOpponent: \(error)") }
        return fallback
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
            let raw = try await session().respond(to: prompt, options: .init(temperature: 0.4)).content
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

    func session() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.instructions)
    }

    static let instructions: String = {
        guard let url = Bundle.main.url(forResource: "BattleAIInstructions", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "You are an expert Pokemon battler." }
        return text
    }()
}
