import SwiftUI

struct PokedexGridView<Pokemon: PokemonViewModelProtocol>: View {
    let pokemon: [Pokemon]
    let grid: GridLayout
    var isLoading: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: grid.layout, spacing: 2.0) {
                ForEach(pokemon, id: \.id) { vm in
                    PokedexGridItem(
                        pokemon: vm,
                        grid: grid
                    )
                }
            }
            .padding(.vertical, 2.0)
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

// MARK: - Grid item
private struct PokedexGridItem<ViewModel: PokemonViewModelProtocol>: View {
    @Namespace private var namespace

    var pokemon: ViewModel
    let grid: GridLayout

    var body: some View {
        NavigationLink {
            PokemonDetailView(viewModel: PokemonDetailViewModel(pokemon: pokemon))
                .navigationTransition(
                    .zoom(sourceID: pokemon.id, in: namespace)
                )
        } label: {
            AsyncSpriteView(
                viewModel: pokemon,
                showOverlay: grid == .three
            )
            .font(.pixel12)
            .matchedTransitionSource(id: pokemon.id, in: namespace)
        }
    }
}
