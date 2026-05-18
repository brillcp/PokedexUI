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
    var playerSummary:   Pokemon { get }
    var opponentSummary: Pokemon { get }
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
    let playerSummary:   Pokemon
    let opponentSummary: Pokemon
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

    private let movePrefetcher:  MovePrefetcher
    private let aiService:       BattleAIServiceProtocol
    private let typeChartLoader: TypeChartLoader

    init(
        player: Pokemon,
        opponent: Pokemon,
        movePrefetcher: MovePrefetcher,
        aiService: BattleAIServiceProtocol,
        typeChart: TypeChartLoader
    ) {
        self.playerSummary  = player
        self.opponentSummary = opponent
        self.movePrefetcher = movePrefetcher
        self.aiService      = aiService
        self.typeChartLoader = typeChart
    }

    var isReady: Bool {
        playerPokemon != nil
            && opponentPokemon != nil
            && !playerMovePool.isEmpty
            && typeChartLoader.chart != nil
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
        let player   = PokemonViewModel(pokemon: playerSummary)
        let opponent = PokemonViewModel(pokemon: opponentSummary)
        self.playerPokemon   = player
        self.opponentPokemon = opponent

        // Make sure every move is persisted in SwiftData before reading.
        // `warmUp` is idempotent: returns instantly once the prefetch has
        // run, otherwise waits for the bulk download to finish here.
        await movePrefetcher.warmUp(modelContainer: modelContext.container)

        let playerMoves  = fetchMoves(for: player,   modelContext: modelContext)
        let opponentPool = fetchMoves(for: opponent, modelContext: modelContext)

        guard playerMoves.count >= maxSelections else {
            errorMessage = "Couldn't load \(playerSummary.name)'s movepool. Check your connection and try again."
            return
        }
        guard opponentPool.count >= maxSelections else {
            errorMessage = "Couldn't load \(opponentSummary.name)'s movepool. Check your connection and try again."
            return
        }

        await typeChartLoader.loadIfNeeded()
        guard let chart = typeChartLoader.chart else {
            errorMessage = "Couldn't load the type chart. Check your connection and try again."
            return
        }

        self.playerMovePool = Self.rankedByImpact(playerMoves)

        // Snapshot the combatants on main (`PokemonViewModel.stats` reads
        // `@Model` fields). `BattleCombatant` is Sendable so the Task can
        // pass it through freely.
        let fighter = BattleCombatant(pokemon: opponent, moves: [])
        let foe     = BattleCombatant(pokemon: player,   moves: [])
        let selectionTarget = maxSelections
        Task { [aiService, opponentPool, chart, fighter, foe] in
            let picks = await aiService.chooseLoadout(
                for: fighter,
                against: foe,
                moves: opponentPool,
                typeChart: chart
            )
            await MainActor.run {
                guard picks.count >= selectionTarget else {
                    self.errorMessage = "Opponent couldn't pick a loadout."
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.opponentLoadout = picks
                }
            }
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

    /// Sample up to 60 names from the pokemon's full movepool and read the
    /// matching `MoveDetail` rows out of SwiftData. The `MovePrefetcher`
    /// awaited above guarantees the rows are persisted (or the prepare
    /// flow has already surfaced an error).
    func fetchMoves(for pokemon: PokemonViewModel, modelContext: ModelContext) -> [MoveDetail] {
        let names = pokemon.pokemon.moves.map(\.move.name)
        guard !names.isEmpty else { return [] }
        let capped = Set(names.shuffled().prefix(60))
        let descriptor = FetchDescriptor<MoveDetail>(
            predicate: #Predicate { capped.contains($0.name) }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
