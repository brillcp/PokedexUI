import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: Private properties
    @Namespace private var namespace

    private let gridLayout: [GridItem] = [
        GridItem(.flexible(maximum: .infinity)),
        GridItem(.flexible(maximum: .infinity))
    ]

    // MARK: - Public properties
    @ObservedObject var viewModel: ViewModel

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            TabView {
                pokemonGridView
                    .tabItem {
                        Label("Pokedex", systemImage: "square.grid.2x2.fill")
                    }
                itemsListView
                    .tabItem {
                        Label("Items", systemImage: "square.fill.on.circle.fill")
                    }
            }
            .applyPokedexStyling()
        }
        .task { await viewModel.requestPokemon() }
    }
}

// MARK: - Tab Views
private extension PokedexView {
    var pokemonGridView: some View {
        ScrollView(showsIndicators: false) {
            pokemonGrid

            if viewModel.isLoading {
                loadingIndicator
            }
        }
        .background(Color.darkGrey)
        .font(.pixel17)
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
            DetailView(viewModel: pokemon)
                .navigationTransition(
                    .zoom(sourceID: pokemon.id, in: namespace)
                )
        } label: {
            pokemonCard(for: pokemon)
                .matchedTransitionSource(id: pokemon.id, in: namespace)
        }
    }

    func pokemonCard(for pokemon: PokemonViewModel) -> some View {
        AsyncGridItem(viewModel: pokemon)
            .overlay(alignment: .bottom) {
                cardOverlay(for: pokemon)
            }
            .task {
                if pokemon == viewModel.pokemon.last {
                    await viewModel.requestPokemon()
                }
            }
    }

    func cardOverlay(for pokemon: PokemonViewModel) -> some View {
        VStack {
            HStack {
                Spacer()
                numberBadge(for: pokemon)
            }
            Spacer()
            pokemonName(for: pokemon)
        }
        .padding(.bottom)
    }
}

// MARK: - Supporting Components
private extension PokedexView {
    func numberBadge(for pokemon: PokemonViewModel) -> some View {
        Text("#\(pokemon.id)")
            .foregroundColor(pokemon.isLight ? .black : .white)
            .padding(8)
    }

    func pokemonName(for pokemon: PokemonViewModel) -> some View {
        Text(pokemon.name)
            .foregroundStyle(pokemon.isLight ? .black : .white)
    }

    var loadingIndicator: some View {
        ProgressView()
            .tint(.white)
    }
}

// MARK: - View Modifiers
private extension View {
    func applyPokedexStyling() -> some View {
        self
            .tint(.pokedexRed)
            .navigationTitle("Pokedex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokedexRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
