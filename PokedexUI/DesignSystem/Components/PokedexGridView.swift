import SwiftUI

/// Grid of `PokemonSummary` rows used by the pokedex, search, and bookmarks
/// tabs. Tapping a cell pushes `PokemonDetailView`, which then lazy-hydrates
/// the full pokemon. `isLoading` only shows a spinner on a cold start when
/// the summary list is still empty.
struct PokedexGridView: View {
    @Namespace private var namespace

    let pokemon: [PokemonSummary]
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
            if isLoading && pokemon.isEmpty {
                ProgressView()
                    .tint(.white)
            }
        }
        .navigationDestination(for: PokemonSummary.self) { vm in
            PokemonDetailView(viewModel: PokemonDetailViewModel(summary: vm))
                .navigationTransition(.zoom(sourceID: vm.id, in: namespace))
        }
    }
}

// MARK: - Grid item

private struct PokedexGridItem: View {
    let pokemon: PokemonSummary
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
