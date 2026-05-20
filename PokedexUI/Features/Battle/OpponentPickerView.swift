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
            .scrollIndicators(.hidden)
            .foregroundStyle(.white)
            .safeAreaBar(edge: .bottom) { pickerButton }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .applyPokedexStyling(title: "Pick opponent", color: .darkGrey)
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
        let pool = Array(balancedCandidates().shuffled().prefix(40))
        warmBattleCaches()
        runOpponentPick(pool: pool)
    }

    func balancedCandidates() -> [Pokemon] {
        let playerBST = player.stats.map(\.baseStat).reduce(0, +)
        let chart = container.typeChart.chart
        let resolvedPlayerTypes = playerTypes.isEmpty
            ? player.types.map(\.type.name)
            : playerTypes
        let filtered = allPokemon.filter { candidate in
            let bst = candidate.stats.map(\.baseStat).reduce(0, +)
            guard abs(bst - playerBST) <= 120 else { return false }
            guard let chart, !resolvedPlayerTypes.isEmpty else { return true }
            let candTypes = candidate.types.map(\.type.name)
            guard !candTypes.isEmpty else { return true }
            let candidatePressure = candTypes
                .map { chart.multiplier(attacking: $0, defenders: resolvedPlayerTypes) }
                .max() ?? 1
            let playerPressure = resolvedPlayerTypes
                .map { chart.multiplier(attacking: $0, defenders: candTypes) }
                .max() ?? 1
            // Hard counter: opponent hits player 2x+ STAB while resisting back.
            if candidatePressure >= 2, playerPressure < 1.5 { return false }
            // Total wall: player's STAB is fully immuned (e.g. Normal vs Ghost).
            if playerPressure == 0 { return false }
            return true
        }
        return filtered.count >= 40 ? filtered : allPokemon
    }

    func warmBattleCaches() {
        let modelContainer = modelContext.container
        let appContainer = container
        Task.detached(priority: .background) {
            await appContainer.movePrefetcher.warmUp(modelContainer: modelContainer)
        }
        Task { @MainActor in
            await appContainer.typeChart.warmUp(modelContainer: modelContainer)
        }
    }

    func runOpponentPick(pool: [Pokemon]) {
        let playerSnapshot = OpponentCandidateSnapshot.player(player, fallbackTypes: playerTypes)
        let candidateSnapshots = pool.map(OpponentCandidateSnapshot.candidate)
        let aiService = container.battleAI
        Task {
            let pickedId = await aiService.chooseOpponent(
                player: playerSnapshot,
                candidates: candidateSnapshots,
                typeChart: container.typeChart.chart
            )
            isAIThinking = false
            if let pickedId, let match = allPokemon.first(where: { $0.id == pickedId }) {
                setupOpponent = match
            } else {
                setupOpponent = pool.randomElement()
            }
        }
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

