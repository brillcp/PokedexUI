import SwiftUI
import SwiftData

/// Sheet shown from `PokemonDetailView` to choose a battle opponent. Backed by
/// `PokemonSummary` rows (the same lightweight store the pokedex grid uses), so
/// the picker pops instantly even on a cold install where full pokemon haven't
/// been hydrated yet.
///
/// The picker owns its own `NavigationStack` so tapping an opponent pushes
/// `BattleSetupView` on top — system back returns to the picker, "Battle!"
/// dismisses the whole sheet and bubbles the launch payload up to the detail
/// view, which then pushes `BattleView` on its own nav stack.
struct OpponentPickerView: View {
    let player: PokemonSummary
    let onStart: (BattleLaunch) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.container) private var container
    @Query private var allPokemon: [PokemonSummary]
    @State private var rows: [Row] = []
    /// `true` while the AI service is picking — disables both bottom buttons
    /// so Random can't race the model response.
    @State private var isAIThinking = false
    /// When non-nil, pushes `BattleSetupView` onto this view's nav stack.
    @State private var setupOpponent: PokemonSummary?

    init(player: PokemonSummary, onStart: @escaping (BattleLaunch) -> Void) {
        self.player = player
        self.onStart = onStart
        // Exclude the player from the candidate list. Sort by id (pokedex order).
        let playerId = player.id
        _allPokemon = Query(
            filter: #Predicate<PokemonSummary> { $0.id != playerId },
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
                    ForEach(rows) { row in
                        OpponentCard(row: row, onTap: select(rowId:))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(.white)
            .overlay(alignment: .bottom) { pickerButtons }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .applyPokedexStyling(title: "Pick opponent", color: .black)
            .navigationDestination(item: $setupOpponent) { opp in
                BattleSetupView(
                    viewModel: BattleSetupViewModel(
                        player: player,
                        opponent: opp,
                        pokemonService: container.pokemonService,
                        moveService: container.moveService
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
        .task(id: allPokemon.count) {
            // Materialise plain-struct rows once; subsequent body renders never
            // touch the SwiftData getters.
            rows = allPokemon.map(Row.init)
        }
    }

    /// Convert a row id back into the underlying summary and push setup.
    private func select(rowId: Int) {
        guard let match = allPokemon.first(where: { $0.id == rowId }) else { return }
        setupOpponent = match
    }

    /// Floating capsule glass buttons anchored at the bottom: dice for a
    /// pure-random pick, sparkles to ask the on-device AI for a "worthy"
    /// opponent. Both buttons disable while the model is thinking so Random
    /// can't race the AI mid-pick.
    private var pickerButtons: some View {
        HStack(spacing: 12) {
            capsuleButton(icon: "die.face.5.fill", title: "Random", action: pickRandom)
            capsuleButton(
                icon: isAIThinking ? "hourglass" : "sparkles",
                title: isAIThinking ? "Thinking" : "Smart pick",
                action: pickSmart
            )
        }
        .disabled(isAIThinking)
        .opacity(isAIThinking ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.15), value: isAIThinking)
        .padding(.bottom, 32)
        .padding(.horizontal, 24)
    }

    private func capsuleButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.pixel14)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
        }
        .glassEffect(.clear.tint(.pokedexRed?.opacity(0.7)).interactive(), in: Capsule())
    }

    private func pickRandom() {
        guard let pick = allPokemon.randomElement() else { return }
        setupOpponent = pick
    }

    /// Sample a smaller candidate pool first (the AI prompt has a token
    /// budget — feeding it 1025 names is wasteful), then hand off to the AI.
    /// Service has internal fallback to a random pick on model failure.
    private func pickSmart() {
        isAIThinking = true
        Task {
            let candidates = Array(allPokemon.shuffled().prefix(60))
            let pick = await container.battleAI.chooseOpponent(
                for: player,
                candidates: candidates
            )
            isAIThinking = false
            setupOpponent = pick
        }
    }
}

// MARK: - Row + cell

extension OpponentPickerView {
    /// Display snapshot — plain value type, no SwiftData getters in body path.
    struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
        let spriteURL: String

        init(_ summary: PokemonSummary) {
            self.id = summary.id
            self.name = summary.name.capitalized
            self.spriteURL = summary.frontSprite
        }
    }
}

private struct OpponentCard: View, Equatable {
    let row: OpponentPickerView.Row
    let onTap: (Int) -> Void

    static func == (lhs: OpponentCard, rhs: OpponentCard) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        Button {
            onTap(row.id)
        } label: {
            VStack(spacing: 4) {
                SpritePlaceholder(url: row.spriteURL)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                Text(row.name)
                    .font(.pixel12)
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.04))
        }
        .buttonStyle(.plain)
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
