import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: Private properties
    @Namespace private var namespace

    private var gridLayout: [GridItem] = [
        GridItem(.flexible(maximum: .infinity)),
        GridItem(.flexible(maximum: .infinity)),
    ]

    // MARK: - Public properties
    @ObservedObject var viewModel: ViewModel

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
            TabView {
                pokemonGridView
                    .tabItem {
                        Label("Pokedex", systemImage: "square.grid.2x2.fill")
                    }
                placeholderTabView
                    .tabItem {
                        Label("Items", systemImage: "square.fill.on.circle.fill")
                    }
            }
            .tint(.pokedexRed)
            .navigationTitle("Pokedex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokedexRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await viewModel.requestPokemon()
        }
    }
}

// MARK: - View Components
private extension PokedexView {
    var pokemonGridView: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: gridLayout) {
                ForEach(viewModel.pokemon, id: \.id) {
                    pokemonGridItem(for: $0)
                        .padding(8)
                }
            }
            .padding(8)

            if viewModel.isLoading {
                loadingView
            }
        }
        .background(Color.darkGrey)
        .font(.pixel17)
    }

    func pokemonGridItem(for pokemon: PokemonViewModel) -> some View {
        NavigationLink {
            DetailView(viewModel: pokemon)
                .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
        } label: {
            gridItem(pokemon: pokemon)
        }
        .tag(pokemon.id)
    }

    func gridItem(pokemon: PokemonViewModel) -> some View {
        AsyncGridItem(viewModel: pokemon)
            .overlay(alignment: .bottom) {
                VStack {
                    HStack {
                        Spacer()
                        NumberOverlay(
                            number: pokemon.id,
                            isLight: pokemon.isLight
                        )
                    }
                    Spacer()
                    Text(pokemon.name)
                }
                .padding(.bottom, 8)
                .foregroundStyle(pokemon.isLight ? .black : .white)
            }
            .task {
                if pokemon == viewModel.pokemon.last {
                    await viewModel.requestPokemon()
                }
            }
    }

    var loadingView: some View {
        ProgressView()
            .tint(.white)
    }

    var placeholderTabView: some View {
        Text("dladl")
    }
}

// MARK: - Supporting Views
private struct NumberOverlay: View {
    let number: Int
    let isLight: Bool

    var body: some View {
        Text("#\(number)")
            .foregroundColor(isLight ? .black : .white)
            .padding(10)
    }
}

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
