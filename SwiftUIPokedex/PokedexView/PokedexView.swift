import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: Private properties
    @Namespace private var namespace

    private let gridLayout: [GridItem] = [
        GridItem(.flexible(maximum: .infinity)),
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
        TabView {
            NavigationStack {
                pokemonGridView
                    .applyPokedexStyling(title: "Pokedex")
            }
            .tabItem {
                Label("Pokedex", systemImage: "square.grid.3x3.fill")
            }

            NavigationStack {
                itemsListView
                    .applyPokedexStyling(title: "Items")
            }
            .tabItem {
                Label("Items", systemImage: "xmark.triangle.circle.square.fill")
            }
        }
        .tint(Color.pokedexRed)
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
        .padding(.bottom, 10)
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

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
