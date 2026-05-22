import SwiftUI
import SwiftData

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
    @State private var candidateCache: [OpponentCandidate]?

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
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(maximum: .infinity), spacing: 2),
                        GridItem(.flexible(maximum: .infinity), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    ForEach(allPokemon, id: \.id) { pokemon in
                        Button {
                            setupOpponent = pokemon
                        } label: {
                            PokemonSpriteCard(pokemon: pokemon)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .disabled(isAIThinking)
            .opacity(isAIThinking ? Opacity.disabled : 1)
            .animation(.easeInOut(duration: 0.2), value: isAIThinking)
            .scrollIndicators(.hidden)
            .foregroundStyle(.white)
            .safeAreaBar(edge: .bottom) { pickerButton }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .applyPokedexStyling(title: "Pick opponent", color: .darkGrey)
            .task {
                await container.movePrefetcher.warmUp(modelContainer: modelContext.container)
            }
            .task(id: allPokemon.count) {
                await prebuildCandidatesIfNeeded()
            }
            .navigationDestination(item: $setupOpponent) { opp in
                BattleSetupView(
                    viewModel: BattleSetupViewModel(
                        player: player,
                        opponent: opp,
                        movePrefetcher: container.movePrefetcher,
                        aiService: container.battleAI,
                        typeChart: container.typeChart
                    ),
                    onStart: { launch in
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
            icon: "sparkle",
            title: "Random",
            isEnabled: !isAIThinking,
            isLoading: isAIThinking,
            action: pickSmart
        )
        .padding(.horizontal, 24)
    }

    func pickSmart() {
        guard !allPokemon.isEmpty, !isAIThinking else { return }
        isAIThinking = true

        let playerCandidate = OpponentCandidate(pokemon: player, fallbackTypes: playerTypes)
        let chart = container.typeChart.chart
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
    func ensureCandidates() async -> [OpponentCandidate] {
        if let cached = candidateCache { return cached }
        let built = await buildCandidates(from: allPokemon)
        candidateCache = built
        return built
    }

    func buildCandidates(from pokemons: [Pokemon]) async -> [OpponentCandidate] {
        var result: [OpponentCandidate] = []
        result.reserveCapacity(pokemons.count)
        for (index, pokemon) in pokemons.enumerated() {
            result.append(OpponentCandidate(pokemon: pokemon))
            if index % 16 == 15 { await Task.yield() }
        }
        return result
    }
}

/// Sprite-over-name grid cell for the opponent picker.
struct PokemonSpriteCard: View, Equatable {
    let pokemon: Pokemon

    var body: some View {
        VStack(spacing: 12) {
            SpriteImage(url: pokemon.frontSprite)
                .frame(height: 92)
            Text(pokemon.name)
                .font(.pixel12)
            HStack {
                ForEach(pokemon.types) { type in
                    Chip(
                        type.type.name.uppercased(),
                        style: .custom(background: TypeColor.color(for: type.type.name))
                    )
                }
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
    }
}
