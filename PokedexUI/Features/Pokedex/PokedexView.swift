import SwiftUI
import SwiftData

/// Root tab host for pokedex, items, favourites, and search.
struct PokedexView<PokedexViewModel: PokedexViewModelProtocol, ItemListViewModel: ItemListViewModelProtocol>: View {
    @State var viewModel: PokedexViewModel
    let itemListViewModel: ItemListViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            Tab(Tabs.pokedex.title, systemImage: viewModel.grid.icon, value: Tabs.pokedex) {
                pokedexTab
            }
            Tab(Tabs.items.title, systemImage: Tabs.items.icon, value: Tabs.items) {
                itemsTab
            }
            Tab(Tabs.favourites.title, systemImage: Tabs.favourites.icon, value: Tabs.favourites) {
                favouritesTab
            }
            Tab(Tabs.search.title, systemImage: Tabs.search.icon, value: Tabs.search, role: .search) {
                searchTab
            }
        }
        .applyPokedexConfiguration(viewModel: viewModel)
    }
}

// MARK: - Private
private extension PokedexView {
    var pokedexTab: some View {
        PokedexContent(viewModel: viewModel)
    }

    var itemsTab: some View {
        NavigationStack {
            ItemListView(viewModel: itemListViewModel)
                .applyPokedexStyling(title: Tabs.items.title)
        }
    }

    var searchTab: some View {
        NavigationStack {
            SearchView(
                viewModel: SearchViewModel(),
                selectedTab: $viewModel.selectedTab
            )
            .applyPokedexStyling(title: Tabs.search.title)
        }
    }

    var favouritesTab: some View {
        NavigationStack {
            BookmarksView()
                .applyPokedexStyling(title: Tabs.favourites.title)
        }
    }
}

/// Pokedex tab content with grid and toolbar.
private struct PokedexContent<ViewModel: PokedexViewModelProtocol>: View {
    @Query(sort: \Pokemon.id) private var corpus: [Pokemon]

    let viewModel: ViewModel

    var body: some View {
        NavigationStack {
            PokedexGridView(
                pokemon: corpus.sorted(by: viewModel.sortType.comparator),
                grid: viewModel.grid,
                isLoading: viewModel.isLoading,
                loadingProgress: viewModel.loadingProgress
            )
            .applyPokedexStyling(title: Tabs.pokedex.title)
            .toolbar { PokedexToolbar(viewModel: viewModel) }
            .animation(.snappy(duration: 0.25), value: viewModel.sortType)
        }
    }
}

/// Pokedex toolbar with grid toggle and sort menu.
private struct PokedexToolbar<ViewModel: PokedexViewModelProtocol & Sendable>: ToolbarContent {
    @State var viewModel: ViewModel

    var body: some ToolbarContent {
        ToolbarItem { gridLayoutButton }
        ToolbarItem { sortMenu }
    }

    private var gridLayoutButton: some View {
        Button("", systemImage: viewModel.grid.otherIcon) {
            withAnimation(.bouncy(duration: 0.25)) { viewModel.grid.toggle() }
        }
    }

    private var sortMenu: some View {
        Menu {
            Label("Sort by", systemImage: "arrow.up.and.down.text.horizontal")
            ForEach(SortType.allCases, id: \.self) { type in
                Button {
                    viewModel.sortType = type
                } label: {
                    Label(type.title, systemImage: type.systemImage)
                }
            }
        } label: {
            Image(systemName: "arrow.up.and.down.text.horizontal")
        }
    }
}

// MARK: - Private
private extension TabView {
    @MainActor
    func applyPokedexConfiguration<ViewModel: PokedexViewModelProtocol>(
        viewModel: ViewModel
    ) -> some View {
        self
            .task { await viewModel.requestPokemon() }
            .colorScheme(.dark)
    }
}

#Preview {
    @Previewable
    @Environment(\.modelContext) var modelContext
    PokedexView(
        viewModel: PokedexViewModel(modelContext: modelContext, container: .live),
        itemListViewModel: ItemListViewModel(modelContext: modelContext, container: .live)
    )
}
