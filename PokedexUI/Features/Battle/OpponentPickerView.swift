import SwiftUI
import SwiftData
import PokeBattleKit

/// Sheet for choosing a battle opponent from the full pokedex.
struct OpponentPickerView: View {
    let player: Pokemon
    let playerTypes: [String]
    let onStart: (BattleLaunch) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext
    @Query private var allPokemon: [Pokemon]
    @State private var isAIThinking = false
    @State private var setupOpponent: Pokemon?
    @State private var candidateCache: [Candidate]?

    init(
        player: Pokemon,
        playerTypes: [String] = [],
        onStart: @escaping (BattleLaunch) -> Void
    ) {
        self.player = player
        self.playerTypes = playerTypes
        self.onStart = onStart
        let playerId = player.id
        _allPokemon = Query(
            filter: #Predicate<Pokemon> { $0.id != playerId },
            sort: \.id
        )
    }

    var body: some View {
        NavigationStack {
            PokemonPickerGrid(pokemon: allPokemon, onSelect: { setupOpponent = $0 })
                .opacity(isAIThinking ? Opacity.disabled : 1)
                .safeAreaBar(edge: .bottom) { pickerButton }
                .disabled(isAIThinking)
                .animation(.easeInOut(duration: 0.2), value: isAIThinking)
                .foregroundStyle(.white)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel, action: dismiss.callAsFunction)
                    }
                }
                .applyPokedexStyling(title: "Pick opponent", navColor: .darkGrey)
                .task(id: allPokemon.count) {
                    await prebuildCandidatesIfNeeded()
                }
                .navigationDestination(item: $setupOpponent) { opp in
                    BattleSetupView(
                        viewModel: BattleSetupViewModel(
                            player: player,
                            opponent: opp,
                            aiService: container.battleAI
                        ), onStart: { launch in
                            dismiss()
                            onStart(launch)
                        }
                    )
                }
        }
    }
}

// MARK: - Private
private extension OpponentPickerView {
    var pickerButton: some View {
        PrimaryCapsuleButton(
            icon: "sparkles.2",
            title: "Smart pick",
            isEnabled: !isAIThinking,
            isLoading: isAIThinking,
            action: pickSmart
        )
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    func pickSmart() {
        guard !allPokemon.isEmpty, !isAIThinking else { return }
        isAIThinking = true

        let playerCandidate = Candidate(pokemon: player, fallbackTypes: playerTypes)
        let chart: TypeChart? = PokeBattleKit.isInitialized ? PokeBattleKit.typeChart : nil
        let aiService = container.battleAI

        Task {
            let candidates = await ensureCandidates()

            let pool = await Task.detached(priority: .userInitiated) {
                OpponentStrategy.balancedPool(
                    from: candidates,
                    playerBST: playerCandidate.baseStatTotal,
                    playerTypes: playerCandidate.typeNames,
                    chart: chart
                )
            }.value

            let pickedId = await aiService.chooseOpponent(
                player: playerCandidate,
                candidates: pool,
                typeChart: chart
            )
            isAIThinking = false
            if let pickedId, let match = allPokemon.first(where: { $0.id == pickedId }) {
                setupOpponent = match
            } else if let id = pool.randomElement()?.id,
                      let match = allPokemon.first(where: { $0.id == id }) {
                setupOpponent = match
            }
        }
    }

    /// Builds the candidate cache on view appear so a "Random" tap can
    /// jump straight to scoring without paying the SwiftData traversal
    /// cost mid-animation.
    func prebuildCandidatesIfNeeded() async {
        guard candidateCache == nil, !allPokemon.isEmpty else { return }
        candidateCache = await buildCandidates(from: allPokemon)
    }

    /// Returns the cached candidates, building them if the prebuild
    /// hasn't completed yet (fallback for an eager Random tap).
    func ensureCandidates() async -> [Candidate] {
        if let cached = candidateCache { return cached }
        let built = await buildCandidates(from: allPokemon)
        candidateCache = built
        return built
    }

    func buildCandidates(from pokemons: [Pokemon]) async -> [Candidate] {
        var result: [Candidate] = []
        result.reserveCapacity(pokemons.count)
        for (index, pokemon) in pokemons.enumerated() {
            result.append(Candidate(pokemon: pokemon))
            if index % 16 == 15 { await Task.yield() }
        }
        return result
    }
}
