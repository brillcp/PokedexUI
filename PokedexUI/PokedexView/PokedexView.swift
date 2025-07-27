import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: Private properties
    @State private var grid: GridLayout = .three
    @Binding private var viewModel: ViewModel
    @Namespace private var namespace

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self._viewModel = .constant(viewModel)
    }

    // MARK: - Body
    var body: some View {
        TabView {
            Tab("Pokedex", systemImage: grid.icon) {
                pokemonGridView
            }

            Tab("Items", systemImage: "xmark.triangle.circle.square.fill") {
                itemsListView
            }

            Tab("Searcj", systemImage: "magnifyingglass", role: .search) {
                searchView
            }
        }
        .tint(Color.pokedexRed)
        .colorScheme(.dark)
        .task { await viewModel.requestPokemon() }
    }
}

// MARK: - Tab Views
private extension PokedexView {
    var pokemonGridView: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                pokemonGrid

                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .font(.pixel12)
            .toolbar {
                ToolbarItem {
                    Button("", systemImage: grid.otherIcon) {
                        withAnimation(.bouncy) {
                            grid.toggle()
                        }
                    }
                    .tint(.white)
                }
            }
            .applyPokedexStyling(title: "Pokedex")
        }
    }

    var itemsListView: some View {
        NavigationStack {
            ItemsListView(viewModel: ItemsListViewModel())
                .applyPokedexStyling(title: "Items")
        }
    }

    var searchView: some View {
        NavigationStack {
            SearchView(viewModel: SearchViewModel(pokemon: viewModel.pokemon))
                .applyPokedexStyling(title: "Search")
        }
    }
}

// MARK: - Grid Components
private extension PokedexView {
    var pokemonGrid: some View {
        LazyVGrid(columns: grid.layout) {
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
        AsyncImageView(
            viewModel: pokemon,
            showOverlay: grid == .three
        )
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
