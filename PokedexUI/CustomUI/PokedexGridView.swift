import SwiftUI

struct PokedexGridView<Pokemon: PokemonViewModel>: View {
    let pokemon: [Pokemon]
    let grid: GridLayout
    let isLoading: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: grid.layout) {
                ForEach(pokemon, id: \.id) { vm in
                    PokedexGridItem(
                        pokemon: vm,
                        grid: grid
                    )
                    .padding(8)
                }
            }
            .padding(8)
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
private struct PokedexGridItem<ViewModel: PokemonViewModel>: View {
    @Namespace private var namespace

    let pokemon: ViewModel
    let grid: GridLayout

    var body: some View {
        NavigationLink {
            PokemonDetailView(viewModel: pokemon)
                .navigationTransition(
                    .zoom(sourceID: pokemon.id, in: namespace)
                )
        } label: {
            AsyncImageView(
                viewModel: pokemon,
                showOverlay: grid == .three
            )
            .font(.pixel12)
            .matchedTransitionSource(id: pokemon.id, in: namespace)
        }
    }
}
