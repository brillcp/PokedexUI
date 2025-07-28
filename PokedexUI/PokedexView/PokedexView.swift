import SwiftUI

enum Tabs: Int {
    case pokedex, items, search
}

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    @State var viewModel: ViewModel

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
                grid: viewModel.grid,
                isLoading: viewModel.isLoading
            )
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
            SearchView(viewModel: SearchViewModel(pokemon: viewModel.pokemon), selectedTab: $viewModel.selectedTab)
                .applyPokedexStyling(title: "Search")
        }
    }
}

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
