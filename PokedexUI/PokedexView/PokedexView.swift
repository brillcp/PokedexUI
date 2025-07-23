import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: Private properties
    @Binding private var viewModel: ViewModel
    @Namespace private var namespace

    private let gridLayout: [GridItem] = [
        GridItem(.flexible(maximum: .infinity)),
        GridItem(.flexible(maximum: .infinity)),
        GridItem(.flexible(maximum: .infinity))
    ]

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self._viewModel = .constant(viewModel)
    }

    // MARK: - Body
    var body: some View {
        TabView {
            NavigationStack {
                pokemonGridView
                    .applyPokedexStyling(title: "Pokedex")
            }
            .tabItem { Label("Pokedex", systemImage: "square.grid.3x3.fill") }

            NavigationStack {
                itemsListView
                    .applyPokedexStyling(title: "Items")
            }
            .tabItem { Label("Items", systemImage: "xmark.triangle.circle.square.fill") }
        }
        .tint(Color.pokedexRed)
        .tabBarMinimizeBehavior(.onScrollDown)
        .colorScheme(.dark)
        .task { await viewModel.requestPokemon() }
    }
}

// MARK: - Tab Views
private extension PokedexView {
    var pokemonGridView: some View {
        ScrollView(showsIndicators: false) {
            pokemonGrid

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
        .font(.pixel12)
    }

    var itemsListView: some View {
        ItemsListView(viewModel: ItemsListViewModel())
    }
}

// MARK: - Grid Components
private extension PokedexView {
    var pokemonGrid: some View {
        LazyVGrid(columns: gridLayout) {
            ForEach(viewModel.pokemon, id: \.id) { pokemon in
                pokemonGridItem(for: pokemon)
                    .padding(8)
            }
        }
        .padding(8)
    }

    func pokemonGridItem(for pokemon: PokemonViewModel) -> some View {
        NavigationLink {
            PokemonDetailView(viewModel: pokemon)
                .navigationTransition(
                    .zoom(sourceID: pokemon.id, in: namespace)
                )
        } label: {
            pokemonCard(for: pokemon)
                .matchedTransitionSource(id: pokemon.id, in: namespace)
        }
    }

    func pokemonCard(for pokemon: PokemonViewModel) -> some View {
        AsyncImageView(viewModel: .constant(pokemon))
            .task {
                if pokemon == viewModel.pokemon.last {
                    await viewModel.requestPokemon()
                }
            }
    }
}

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
