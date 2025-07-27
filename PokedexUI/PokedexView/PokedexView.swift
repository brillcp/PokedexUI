import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: Private properties
    @State private var grid: GridLayout = .three
    @Binding private var viewModel: ViewModel

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
            PokedexGridView(
                pokemon: viewModel.pokemon,
                grid: grid,
                isLoading: viewModel.isLoading
            )
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

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
