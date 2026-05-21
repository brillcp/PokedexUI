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
    @State private var snapshotCache: [OpponentCandidateSnapshot]?

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
                .animation(.easeInOut(duration: 0.2), value: isAIThinking)
            }
            .disabled(isAIThinking)
            .opacity(isAIThinking ? 0.5 : 1)
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
            icon: isAIThinking ? "hourglass" : "sparkles.2",
            title: isAIThinking ? "Thinking" : "Random",
            isEnabled: !isAIThinking,
            action: pickSmart
        )
        .padding(.horizontal, 24)
    }

    func pickSmart() {
        guard !allPokemon.isEmpty, !isAIThinking else { return }
        isAIThinking = true

        let playerSnapshot = OpponentCandidateSnapshot.player(player, fallbackTypes: playerTypes)
        let chart = container.typeChart.chart
        let aiService = container.battleAI
        let pokemons = allPokemon

        Task {
            let snapshots: [OpponentCandidateSnapshot]
            if let cached = snapshotCache {
                snapshots = cached
            } else {
                snapshots = await buildCandidateSnapshots(from: pokemons)
                snapshotCache = snapshots
            }

            let pool = await Task.detached(priority: .userInitiated) {
                OpponentCandidateSnapshot.balancedPool(
                    from: snapshots,
                    playerBST: playerSnapshot.baseStatTotal,
                    playerTypes: playerSnapshot.typeNames,
                    chart: chart
                )
            }.value

            let pickedId = await aiService.chooseOpponent(
                player: playerSnapshot,
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

    func buildCandidateSnapshots(from pokemons: [Pokemon]) async -> [OpponentCandidateSnapshot] {
        var result: [OpponentCandidateSnapshot] = []
        result.reserveCapacity(pokemons.count)
        for (index, pokemon) in pokemons.enumerated() {
            result.append(.candidate(pokemon))
            if index % 64 == 63 { await Task.yield() }
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

