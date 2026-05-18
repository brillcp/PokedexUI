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
    /// Pre-baked AI choice. Kicked off in `.task` the moment the corpus
    /// lands so the model is usually done by the time the user reaches
    /// the bottom button; tapping "Random" then becomes instant.
    @State private var preselectedOpponent: Pokemon?
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
        .task(id: allPokemon.count) { await prebakeOpponent() }
        .task { await warmBattleCaches() }
    }

}

// MARK: - Subviews + actions

private extension OpponentPickerView {
    var pickerButton: some View {
        let ready = preselectedOpponent != nil
        return PrimaryCapsuleButton(
            icon: ready ? "sparkles.2" : "hourglass",
            title: ready ? "Random" : "Thinking",
            isEnabled: ready,
            action: pickPreselected
        )
        .padding(.horizontal, 24)
    }

    /// Push the pre-baked AI pick. Button is disabled until the pick lands
    /// so this never fires with a nil opponent.
    func pickPreselected() {
        guard let pick = preselectedOpponent else { return }
        setupOpponent = pick
    }

    /// Kick off the AI opponent pick the moment the corpus is available.
    /// The result lands on `preselectedOpponent` and the bottom button
    /// flips from "Thinking" to "Random". User taps → instant push.
    func prebakeOpponent() async {
        guard preselectedOpponent == nil, !allPokemon.isEmpty else { return }
        let candidates = Array(allPokemon.shuffled())
        let pick = await container.battleAI.chooseOpponent(
            for: player,
            playerTypes: playerTypes,
            candidates: candidates
        )
        preselectedOpponent = pick
    }

    /// Kick off the two battle-side bootstraps the moment the picker opens so
    /// they overlap with the user scrolling/picking. The type chart is small
    /// and structured (loads inside `.task`); the move prefetch is ~900 rows
    /// and runs detached so it survives a quick dismiss. Both call sites guard
    /// against repeat work, so re-entering the picker is a no-op.
    func warmBattleCaches() async {
        let modelContainer = modelContext.container
        let appContainer = container
        Task.detached(priority: .background) {
            await appContainer.movePrefetcher.attach(modelContainer: modelContainer)
            await appContainer.movePrefetcher.prefetchIfNeeded()
        }
        await appContainer.typeChart.attach(modelContainer: modelContainer)
        await appContainer.typeChart.loadIfNeeded()
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
