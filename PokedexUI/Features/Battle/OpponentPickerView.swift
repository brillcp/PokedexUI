import SwiftUI
import SwiftData

/// Sheet shown from `PokemonDetailView` to choose a battle opponent. Backed by
/// `Pokemon` rows (the same lightweight store the pokedex grid uses), so
/// the picker pops instantly even on a cold install where full pokemon haven't
/// been hydrated yet.
///
/// The picker owns its own `NavigationStack` so tapping an opponent pushes
/// `BattleSetupView` on top. System back returns to the picker; "Battle!"
/// dismisses the whole sheet and bubbles the launch payload up to the detail
/// view, which then pushes `BattleView` on its own nav stack.
struct OpponentPickerView: View {
    let player: Pokemon
    /// Player's type names (e.g. ["grass", "poison"]). Passed straight into
    /// the AI prompt for smart-pick so the model picks against the actual
    /// matchup instead of relying on training recall.
    let playerTypes: [String]
    let onStart: (BattleLaunch) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext
    @Query private var allPokemon: [Pokemon]
    /// `true` while the AI is running on a button-tap. Disables the button
    /// + flips the label to "Thinking" so the user sees the work happen.
    @State private var isAIThinking = false
    /// When non-nil, pushes `BattleSetupView` onto this view's nav stack.
    @State private var setupOpponent: Pokemon?

    init(
        player: Pokemon,
        playerTypes: [String] = [],
        onStart: @escaping (BattleLaunch) -> Void
    ) {
        self.player = player
        self.playerTypes = playerTypes
        self.onStart = onStart
        // Exclude the player from the candidate list. Sort by id (pokedex order).
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
                            PokemonSpriteCard(
                                id: pokemon.id,
                                name: pokemon.name.capitalized,
                                spriteURL: pokemon.frontSprite
                            )
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
                        moveService: container.moveService,
                        aiService: container.battleAI,
                        typeChart: container.typeChart
                    ),
                    onStart: { launch in
                        // Sheet collapses; detail view picks up the launch
                        // and pushes the battle screen.
                        dismiss()
                        onStart(launch)
                    }
                )
            }
        }
    }

}

// MARK: - Subviews + actions

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

    /// Pre-flight check on the main actor (corpus available, no AI run in
    /// flight), snapshot what the AI needs into Sendable structs on main,
    /// then cross to the actor for the model call. Tap path stays on main
    /// only long enough to build snapshots; the AI inference, the move
    /// prefetch, and the type chart load all run in parallel off-main. Once
    /// the AI returns, we map the picked id back to a SwiftData `Pokemon`.
    func pickSmart() {
        guard !allPokemon.isEmpty, !isAIThinking else { return }
        isAIThinking = true

        let pool = Array(allPokemon.shuffled().prefix(40))
        let playerSnapshot = PokemonAISnapshot.player(player, fallbackTypes: playerTypes)
        let candidateSnapshots = pool.map(PokemonAISnapshot.candidate)
        let aiService = container.battleAI
        let modelContainer = modelContext.container
        let appContainer = container

        // Warm the battle-side caches in parallel with the AI inference so
        // the loadout view doesn't pay a cold-start once the user lands.
        Task.detached(priority: .background) {
            await appContainer.movePrefetcher.attach(modelContainer: modelContainer)
            await appContainer.movePrefetcher.prefetchIfNeeded()
        }
        Task { @MainActor in
            await appContainer.typeChart.attach(modelContainer: modelContainer)
            await appContainer.typeChart.loadIfNeeded()
        }

        Task {
            let pickedId = await aiService.chooseOpponent(
                player: playerSnapshot,
                candidates: candidateSnapshots
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

// MARK: - Cell

/// Sprite-over-name grid cell shared by the opponent picker and the search
/// empty-state suggestions. Caller wraps in a `Button` / `NavigationLink` to
/// supply the tap behavior.
struct PokemonSpriteCard: View, Equatable {
    let id: Int
    let name: String
    let spriteURL: String

    static func == (lhs: PokemonSpriteCard, rhs: PokemonSpriteCard) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.spriteURL == rhs.spriteURL
    }

    var body: some View {
        VStack(spacing: 0) {
            SpritePlaceholder(url: spriteURL)
                .frame(height: 92)
                .frame(maxWidth: .infinity)
            Text(name)
                .font(.pixel12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
    }
}

/// Cell-level placeholder: image fades in when ready; circle gray dot before then.
private struct SpritePlaceholder: View, Equatable {
    let url: String

    var body: some View {
        AsyncImage(
            url: URL(string: url),
            transaction: .init(animation: .easeInOut(duration: 0.2))
        ) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
            case .empty, .failure:
                Color(.systemGray4)
                    .clipShape(Circle())
                    .padding(24)
            @unknown default:
                Color(.systemGray4).clipShape(Circle()).padding(24)
            }
        }
    }
}
