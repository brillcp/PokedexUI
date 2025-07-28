import SwiftUI

enum Tabs: Int {
    case pokedex, items, search
}

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: Private properties
    @State private var grid: GridLayout = .three
    @Binding private var viewModel: ViewModel
    @State private var selectedTab: Tabs = .pokedex

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self._viewModel = .constant(viewModel)
    }

    // MARK: - Body
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Pokedex", systemImage: grid.icon, value: Tabs.pokedex) {
                pokedexGridView
            }

            Tab("Items", systemImage: "xmark.triangle.circle.square.fill", value: Tabs.items) {
                itemsListView
            }

            Tab("Search", systemImage: "magnifyingglass", value: Tabs.search, role: .search) {
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
    var pokedexGridView: some View {
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
            SearchView(viewModel: SearchViewModel(pokemon: viewModel.pokemon), selectedTab: $selectedTab)
                .applyPokedexStyling(title: "Search")
        }
    }
}

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
