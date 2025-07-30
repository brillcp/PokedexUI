import SwiftUI
import SwiftData

struct PokedexView<PokedexViewModel: PokedexViewModelProtocol, ItemsListViewModel: ItemsListViewModelProtocol, SearchViewModel: SearchViewModelProtocol>: View {
    @State var viewModel: PokedexViewModel

    let itemsListViewModel: ItemsListViewModel
    let searchViewModel: SearchViewModel

    // MARK: - Body
    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            Tab(Tabs.pokedex.title, systemImage: viewModel.grid.icon, value: Tabs.pokedex) {
                pokedexGridView
            }

            Tab(Tabs.items.title, systemImage: Tabs.items.icon, value: Tabs.items) {
                itemsListView
            }

            Tab(Tabs.search.title, systemImage: Tabs.search.icon, value: Tabs.search, role: .search) {
                searchView
            }

            Tab(Tabs.favourites.title, systemImage: Tabs.favourites.icon, value: Tabs.favourites) {
                favouriteView
            }
        }
        .environment(\.pokemonData, viewModel.pokemon)
        .task { await viewModel.requestPokemon() }
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
            .applyPokedexStyling(title: Tabs.pokedex.title)
            .toolbar {
                ToolbarItem { gridLayoutButton }
                ToolbarItem { sortMenu }
            }
            .tint(.white)
        }
    }

    var itemsListView: some View {
        NavigationStack {
            ItemsListView(viewModel: itemsListViewModel)
                .applyPokedexStyling(title: Tabs.items.title)
        }
    }

    var searchView: some View {
        NavigationStack {
            SearchView(
                viewModel: searchViewModel,
                selectedTab: $viewModel.selectedTab
            )
            .applyPokedexStyling(title: Tabs.search.title)
        }
    }

    var favouriteView: some View {
        NavigationStack {
            BookmarksView()
                .applyPokedexStyling(title: Tabs.favourites.title)
        }
    }

    var gridLayoutButton: some View {
        Button("", systemImage: viewModel.grid.otherIcon) {
            withAnimation(.bouncy) { viewModel.grid.toggle() }
        }
    }

    var sortMenu: some View {
        Menu {
            ForEach(SortType.allCases, id: \.self) { type in
                Button {
                    withAnimation(.bouncy) { viewModel.sort(by: type) }
                } label: {
                    Label(type.title, systemImage: type.systemImage)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
    }
}

#Preview {
    @Previewable
    @Environment(\.modelContext) var modelContext
    PokedexView(
        viewModel: PokedexViewModel(modelContext: modelContext),
        itemsListViewModel: ItemsListViewModel(),
        searchViewModel: SearchViewModel()
    )
}
