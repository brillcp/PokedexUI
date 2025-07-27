import SwiftUI

struct PokemonGridView<ViewModel: PokemonViewModel>: View {
    let pokemon: [ViewModel]
    let grid: GridLayout
    let isLoading: Bool
    let asyncTask: @Sendable () async -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: grid.layout) {
                ForEach(pokemon, id: \.id) { vm in
                    PokemonGridItem(
                        pokemon: vm,
                        grid: grid
                    )
                    .padding(8)
                    .task {
                        if vm == pokemon.last {
                            await asyncTask()
                        }
                    }
                }
            }
            .padding(8)

            if isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

private struct PokemonGridItem<ViewModel: PokemonViewModel>: View {
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
