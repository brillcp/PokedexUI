import SwiftUI
import SwiftData

// MARK: - Main View
struct PokedexView<
    PokedexViewModel: PokedexViewModelProtocol,
    ItemListViewModel: ItemListViewModelProtocol
>: View {
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

// MARK: - Tabs
private extension PokedexView {
    var pokedexTab: some View {
        PokedexContent(viewModel: $viewModel)
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
                viewModel: SearchViewModel(pokemon: viewModel.pokemon),
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

// MARK: - Content Views
private struct PokedexContent<ViewModel: PokedexViewModelProtocol>: View {
    @Binding var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            PokedexGridView(
                pokemon: viewModel.pokemon,
                grid: viewModel.grid,
                isLoading: viewModel.isLoading
            )
            .applyPokedexStyling(title: Tabs.pokedex.title)
            .toolbar { PokedexToolbar(viewModel: $viewModel) }
            .tint(.white)
        }
    }
}

// MARK: - Toolbar
private struct PokedexToolbar<ViewModel: PokedexViewModelProtocol & Sendable>: ToolbarContent {
    @Binding var viewModel: ViewModel

    var body: some ToolbarContent {
        ToolbarItem { gridLayoutButton }
        ToolbarItem { sortMenu }
    }

    private var gridLayoutButton: some View {
        Button("", systemImage: viewModel.grid.otherIcon) {
            withAnimation(.bouncy) { viewModel.grid.toggle() }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortType.allCases, id: \.self) { type in
                Button {
                    Task { await viewModel.sort(by: type) }
                } label: {
                    Label(type.title, systemImage: type.systemImage)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
    }
}

// MARK: - Configuration Extension
private extension TabView {
    @MainActor
    func applyPokedexConfiguration<ViewModel: PokedexViewModelProtocol>(
        viewModel: ViewModel
    ) -> some View {
        self
            .task { await viewModel.requestPokemon() }
            .tint(Color.pokedexRed)
            .colorScheme(.dark)
    }
}

#Preview {
    @Previewable
    @Environment(\.modelContext) var modelContext
    PokedexView(
        viewModel: PokedexViewModel(modelContext: modelContext),
        itemListViewModel: ItemListViewModel(modelContext: modelContext)
    )
}
