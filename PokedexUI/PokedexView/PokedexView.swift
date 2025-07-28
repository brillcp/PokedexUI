import SwiftUI

enum Tabs: Int {
    case pokedex, items, search
}

struct PokedexView<ViewModel: PokedexViewModelProtocol, ItemsListViewModel: ItemsListViewModelProtocol, SearchViewModel: SearchViewModelProtocol>: View {
    @State var viewModel: ViewModel

    let itemsListViewModel: ItemsListViewModel
    let searchViewModel: SearchViewModel

    // MARK: - Body
    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            Tab("Pokedex", systemImage: viewModel.grid.icon, value: Tabs.pokedex) {
                pokedexGridView
            }

            Tab("Items", systemImage: "xmark.triangle.circle.square.fill", value: Tabs.items) {
                itemsListView
            }

            Tab("Search", systemImage: "magnifyingglass", value: Tabs.search, role: .search) {
                searchView
            }
        }
        .environment(\.pokemonData, viewModel.pokemon)
        .tint(Color.pokedexRed)
        .colorScheme(.dark)
    }
}

// MARK: - Tab Views
private extension PokedexView {
    var pokedexGridView: some View {
        NavigationStack {
            PokedexGridView(
                pokemon: viewModel.pokemon,
                grid: viewModel.grid,
                isLoading: viewModel.isLoading
            )
            .applyPokedexStyling(title: "Pokedex")
            .toolbar {
                ToolbarItem {
                    Button("", systemImage: viewModel.grid.otherIcon) {
                        withAnimation(.bouncy) {
                            viewModel.grid.toggle()
                        }
                    }
                    .tint(.white)
                }
            }
        }
    }

    var itemsListView: some View {
        NavigationStack {
            ItemsListView(viewModel: itemsListViewModel)
                .applyPokedexStyling(title: "Items")
        }
    }

    var searchView: some View {
        NavigationStack {
            SearchView(
                viewModel: searchViewModel,
                selectedTab: $viewModel.selectedTab
            )
            .applyPokedexStyling(title: "Search")
        }
    }
}

#Preview {
    PokedexView(
        viewModel: PokedexViewModel(),
        itemsListViewModel: ItemsListViewModel(),
        searchViewModel: SearchViewModel()
    )
}
