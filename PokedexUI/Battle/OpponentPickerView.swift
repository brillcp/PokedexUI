import SwiftUI
import SwiftData

struct OpponentPickerView: View {
    let player: PokemonViewModel
    let onSelect: (PokemonViewModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allPokemon: [Pokemon]

    init(player: PokemonViewModel, onSelect: @escaping (PokemonViewModel) -> Void) {
        self.player = player
        self.onSelect = onSelect
        // Filter and sort at the SwiftData layer so we don't materialise a 1k-element
        // array on every body render.
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
                    ForEach(allPokemon, id: \.id) { opp in
                        opponentCard(opp)
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

    /// Renders directly from the SwiftData model so LazyVGrid only pays the cost
    /// for visible cells. PokemonViewModel is only constructed when the user taps.
    private func opponentCard(_ pokemon: Pokemon) -> some View {
        Button {
            onSelect(PokemonViewModel(pokemon: pokemon))
        } label: {
            VStack(spacing: 4) {
                spriteWithPlaceholder(url: pokemon.sprite.front)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                Text(pokemon.name.capitalized).font(.pixel12)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.04))
        }
        .buttonStyle(.plain)
    }

    /// Renders the cell layout instantly; image fades in once loaded. Placeholder
    /// is a circle so the empty state reads as a coin/icon rather than a square hole.
    @ViewBuilder
    private func spriteWithPlaceholder(url: String?) -> some View {
        AsyncImage(url: url.flatMap(URL.init(string:)), transaction: .init(animation: .easeInOut(duration: 0.2))) { phase in
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
