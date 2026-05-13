import SwiftUI
import SwiftData

struct OpponentPickerView: View {
    let player: PokemonViewModel
    let onSelect: (PokemonViewModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allPokemon: [Pokemon]
    @State private var rows: [Row] = []

    init(player: PokemonViewModel, onSelect: @escaping (PokemonViewModel) -> Void) {
        self.player = player
        self.onSelect = onSelect
        // Filter + sort in SwiftData so we don't pay the cost on every body.
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
                    ForEach(rows) { row in
                        OpponentCard(row: row, onTap: select(rowId:))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(.white)
            .overlay(alignment: .bottom) { randomButton }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .applyPokedexStyling(title: "Pick opponent", color: .black)
        }
        .task(id: allPokemon.count) {
            // Materialise plain-struct rows once; subsequent body renders never
            // touch the SwiftData getters.
            rows = allPokemon.map(Row.init)
        }
    }

    /// Convert a row id back into the underlying `Pokemon` and call the parent.
    private func select(rowId: Int) {
        guard let match = allPokemon.first(where: { $0.id == rowId }) else { return }
        onSelect(PokemonViewModel(pokemon: match))
    }

    /// Floating capsule glass button anchored at the bottom of the screen.
    private var randomButton: some View {
        Button {
            guard let pick = allPokemon.randomElement() else { return }
            onSelect(PokemonViewModel(pokemon: pick))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "die.face.5.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Random")
                    .font(.pixel14)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
        }
        .glassEffect(.clear.tint(.pokedexRed?.opacity(0.4)).interactive(), in: Capsule())
        .padding(.bottom, 32)
        .padding(.horizontal, 24)
    }
}

// MARK: - Row + cell

extension OpponentPickerView {
    /// Display snapshot — plain value type, no SwiftData getters in body path.
    struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
        let spriteURL: String

        init(_ pokemon: Pokemon) {
            self.id = pokemon.id
            self.name = pokemon.name.capitalized
            self.spriteURL = pokemon.sprite.front
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
                    .padding(.bottom, 6)
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
