import SwiftUI

struct PokedexGridView<Pokemon: PokemonViewModelProtocol & Hashable>: View {
    @Namespace private var namespace

    let pokemon: [Pokemon]
    var grid: GridLayout = .three
    var isLoading: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: grid.layout, spacing: 2.0) {
                ForEach(pokemon, id: \.id) { vm in
                    PokedexGridItem(
                        pokemon: vm,
                        grid: grid,
                        namespace: namespace
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
        .navigationDestination(for: Pokemon.self) { vm in
            PokemonDetailView(viewModel: PokemonDetailViewModel(pokemon: vm))
                .navigationTransition(.zoom(sourceID: vm.id, in: namespace))
        }
    }
}

// MARK: - Grid item
private struct PokedexGridItem<ViewModel: PokemonViewModelProtocol & Hashable>: View {
    let pokemon: ViewModel
    let grid: GridLayout
    let namespace: Namespace.ID

    var body: some View {
        NavigationLink(value: pokemon) {
            AsyncSpriteView(
                viewModel: pokemon,
                showOverlay: grid == .three
            )
            .font(.pixel12)
            .matchedTransitionSource(id: pokemon.id, in: namespace)
        }
    }
}
