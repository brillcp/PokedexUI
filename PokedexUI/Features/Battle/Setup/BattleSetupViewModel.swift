import Foundation
import SwiftData
import SwiftUI

/// Pre-battle prep screen. Hydrates both pokemon (cache-first), samples each
/// side's movepool, surfaces the player's pool for hand-picking, and kicks off
/// the AI's loadout pick in a background task so it runs in parallel with the
/// player browsing. `canStart` requires both: player chose 4 AND AI returned 4.
///
/// Conceptually this is the "loadout" step canonical Pokémon battles have .
/// no random movesets, both sides commit to 4 moves before battling.
@MainActor
protocol BattleSetupViewModelProtocol {
    var playerSummary:   PokemonSummary { get }
    var opponentSummary: PokemonSummary { get }
    var playerPokemon:   PokemonViewModel? { get }
    var opponentPokemon: PokemonViewModel? { get }
    /// Hydrated movepool the player picks from (up to 40 sampled).
    var playerMovePool:  [MoveDetail] { get }
    /// Opponent's AI-picked 4-move loadout. `nil` while the AI is thinking,
    /// non-nil once ready. View checks this to enable the Battle button.
    var opponentLoadout: [MoveDetail]? { get }
    /// Names of the 4 currently-selected player moves.
    var selectedMoveNames: Set<String> { get }
    /// True once both sides are hydrated + move pools are filled.
    var isReady: Bool { get }
    /// Maximum allowed picks.
    var maxSelections: Int { get }
    /// Set after a fatal preflight error (network down + cache miss).
    var errorMessage: String? { get }

    /// Hydrate both sides, fetch move pools, kick off AI loadout. Cache-first.
    func prepare(modelContext: ModelContext) async
    /// Toggle a player move's selection. Caps at `maxSelections`.
    func toggle(_ move: MoveDetail)
    /// `true` once `maxSelections` moves are selected AND the AI has finished
    /// picking its 4 moves.
    var canStart: Bool { get }
    /// Player's chosen moves in selection order.
    func playerMoves() -> [MoveDetail]
}

// MARK: - Implementation

/// Live implementation of `BattleSetupViewModelProtocol`. Hydrates both
/// pokemon, samples each side's movepool, and kicks off the AI loadout pick
/// in a detached background task so the player can browse + pick their own
/// 4 moves while the model thinks.
@Observable
final class BattleSetupViewModel: BattleSetupViewModelProtocol {
    let playerSummary:   PokemonSummary
    let opponentSummary: PokemonSummary
    let maxSelections:   Int = 4

    var playerPokemon:    PokemonViewModel?
    var opponentPokemon:  PokemonViewModel?
    var playerMovePool:   [MoveDetail] = []
    var opponentLoadout:  [MoveDetail]?
    var selectedMoveNames: Set<String> = []
    /// Ordered list of selected names so `playerMoves()` returns them in pick
    /// order (matches what the player sees on the grid as they tap).
    private var selectionOrder: [String] = []
    var errorMessage: String?

    private let pokemonService: PokemonServiceProtocol
    private let moveService:    MoveServiceProtocol
    private let aiService:      BattleAIServiceProtocol
    private let typeChartLoader: TypeChartLoader

    init(
        player: PokemonSummary,
        opponent: PokemonSummary,
        pokemonService: PokemonServiceProtocol,
        moveService: MoveServiceProtocol,
        aiService: BattleAIServiceProtocol,
        typeChart: TypeChartLoader
    ) {
        self.playerSummary  = player
        self.opponentSummary = opponent
        self.pokemonService = pokemonService
        self.moveService    = moveService
        self.aiService      = aiService
        self.typeChartLoader = typeChart
    }

    var isReady: Bool {
        playerPokemon != nil && opponentPokemon != nil && !playerMovePool.isEmpty
    }

    /// Player has 4 picks AND opponent loadout is ready.
    var canStart: Bool {
        selectedMoveNames.count == maxSelections && opponentLoadout != nil
    }

    func toggle(_ move: MoveDetail) {
        if selectedMoveNames.contains(move.name) {
            selectedMoveNames.remove(move.name)
            selectionOrder.removeAll { $0 == move.name }
            return
        }
        guard selectedMoveNames.count < maxSelections else { return }
        selectedMoveNames.insert(move.name)
        selectionOrder.append(move.name)
    }

    func playerMoves() -> [MoveDetail] {
        let byName = Dictionary(uniqueKeysWithValues: playerMovePool.map { ($0.name, $0) })
        return selectionOrder.compactMap { byName[$0] }
    }

    // MARK: - Preparation

    func prepare(modelContext: ModelContext) async {
        do {
            async let playerFull   = hydrate(playerSummary,   in: modelContext)
            async let opponentFull = hydrate(opponentSummary, in: modelContext)
            let player   = try await playerFull
            let opponent = try await opponentFull
            self.playerPokemon   = player
            self.opponentPokemon = opponent

            // Both 40-move samples in parallel. Player pool ranked
            // strongest-first so the most useful picks surface at the top.
            async let playerMoves   = fetchMoves(for: player,   modelContext: modelContext)
            async let opponentMoves = fetchMoves(for: opponent, modelContext: modelContext)
            self.playerMovePool = (try? await playerMoves).map(Self.rankedByImpact) ?? []
            let opponentPool    = (try? await opponentMoves) ?? []

            // Kick off the AI loadout pick in a detached background task .
            // player can browse + pick their own 4 while the model thinks.
            // Battle button stays disabled until `opponentLoadout` is non-nil.
            await typeChartLoader.loadIfNeeded()
            let chart = typeChartLoader.chart ?? TypeChart(rows: [])
            // Snapshot the combatants on main (PokemonViewModel.stats reads
            // @Model fields). `BattleCombatant` is Sendable so the Task can
            // pass it through freely.
            let fighter = BattleCombatant(pokemon: opponent, moves: [])
            let foe     = BattleCombatant(pokemon: player,   moves: [])
            Task { [aiService, opponentPool, chart, fighter, foe] in
                let picks = await aiService.chooseLoadout(
                    for: fighter,
                    against: foe,
                    moves: opponentPool,
                    typeChart: chart
                )
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.opponentLoadout = picks
                    }
                }
            }
        } catch {
            self.errorMessage = "Couldn't load battle: \(error.localizedDescription)"
        }
    }

}

// MARK: - Private

private extension BattleSetupViewModel {
    /// Sort movepool so the most useful damaging moves bubble to the top of
    /// the picker grid. Damaging moves before status, then higher power, then
    /// higher accuracy. Player still makes every pick consciously; this only
    /// changes presentation order.
    static func rankedByImpact(_ moves: [MoveDetail]) -> [MoveDetail] {
        moves.sorted { lhs, rhs in
            let lDamage = (lhs.power ?? 0) > 0
            let rDamage = (rhs.power ?? 0) > 0
            if lDamage != rDamage { return lDamage }
            let lp = lhs.power ?? 0
            let rp = rhs.power ?? 0
            if lp != rp { return lp > rp }
            return (lhs.accuracy ?? 100) > (rhs.accuracy ?? 100)
        }
    }

    /// SwiftData-cache-first hydration. Mirrors `PokemonDetailViewModel`'s path
    /// so a pokemon viewed in detail is instant here too.
    func hydrate(_ summary: PokemonSummary, in context: ModelContext) async throws -> PokemonViewModel {
        let id = summary.id
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })
        if let cached = try? context.fetch(descriptor).first {
            return PokemonViewModel(pokemon: cached)
        }
        let fetched = try await pokemonService.requestFullPokemon(id: id)
        context.insert(fetched)
        try? context.save()
        return PokemonViewModel(pokemon: fetched)
    }

    /// Sample up to 40 moves from the pokemon's full movepool and resolve each
    /// against the SwiftData `MoveDetail` cache (filled by `MovePrefetcher` at
    /// app start). Misses fall back to network.
    func fetchMoves(for pokemon: PokemonViewModel, modelContext: ModelContext) async throws -> [MoveDetail] {
        let names = pokemon.pokemon.moves.map(\.move.name)
        guard !names.isEmpty else { return [] }
        let capped = Array(names.shuffled().prefix(40))

        let descriptor = FetchDescriptor<MoveDetail>(
            predicate: #Predicate { capped.contains($0.name) }
        )
        let cached = (try? modelContext.fetch(descriptor)) ?? []
        let cachedByName = Dictionary(uniqueKeysWithValues: cached.map { ($0.name, $0) })

        let missing = capped.filter { cachedByName[$0] == nil }
        var fetched: [MoveDetail] = []
        if !missing.isEmpty {
            fetched = try await moveService.requestMoves(named: missing)
            for move in fetched { modelContext.insert(move) }
            try? modelContext.save()
        }

        let merged = cachedByName.merging(
            Dictionary(uniqueKeysWithValues: fetched.map { ($0.name, $0) }),
            uniquingKeysWith: { lhs, _ in lhs }
        )
        return capped.compactMap { merged[$0] }
    }
}
