import SwiftUI
import SwiftData

/// Root tab host for pokedex, items, favourites, and search. Each tab
/// builds its own view model inline; only the pokedex view model is
/// hoisted here so its grid + sort state survives tab switches.
struct RootTabView<PokedexViewModel: PokedexViewModelProtocol>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.container) private var container

    @State var viewModel: PokedexViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            Tab(Tabs.pokedex.title, systemImage: viewModel.grid.icon, value: Tabs.pokedex) {
                pokedexTab
            }
            Tab(Tabs.battle.title, systemImage: Tabs.battle.icon, value: Tabs.battle) {
                battleTab
            }
            Tab(Tabs.items.title, systemImage: Tabs.items.icon, value: Tabs.items) {
                itemsTab
            }
            Tab(Tabs.search.title, systemImage: Tabs.search.icon, value: Tabs.search, role: .search) {
                searchTab
            }
        }
        .task { await viewModel.requestPokemon() }
        .colorScheme(.dark)
        .sheet(isPresented: $viewModel.openFavourites) {
            favouritesTab
        }
    }
}

// MARK: - Private
private extension RootTabView {
    var pokedexTab: some View {
        PokedexContent(viewModel: viewModel)
    }

    var itemsTab: some View {
        ItemListView(viewModel: ItemListViewModel(modelContext: modelContext, container: container))
    }

    var searchTab: some View {
        SearchView(
            viewModel: SearchViewModel(),
            selectedTab: $viewModel.selectedTab
        )
    }

    var favouritesTab: some View {
        BookmarksView()
    }

    var battleTab: some View {
        MultiplayerSetupView(container: container)
    }
}

/// Pokedex tab content with grid and toolbar.
private struct PokedexContent<ViewModel: PokedexViewModelProtocol>: View {
    let viewModel: ViewModel

    var body: some View {
        NavigationStack {
            PokedexGridView(
                pokemon: viewModel.pokemon.sorted(by: viewModel.sortType.comparator(direction: viewModel.sortDirection)),
                grid: viewModel.grid,
                isLoading: viewModel.isLoading,
                loadingProgress: viewModel.loadingProgress
            )
            .applyPokedexStyling(title: Tabs.pokedex.title)
            .toolbar { PokedexToolbar(viewModel: viewModel) }
            .animation(.snappy(duration: 0.25), value: viewModel.sortType)
            .animation(.snappy(duration: 0.25), value: viewModel.sortDirection)
        }
    }
}

/// Pokedex toolbar with grid toggle and sort menu.
private struct PokedexToolbar<ViewModel: PokedexViewModelProtocol & Sendable>: ToolbarContent {
    @State var viewModel: ViewModel

    var body: some ToolbarContent {
        ToolbarItem { gridLayoutButton }
        ToolbarItem { sortMenu }
        ToolbarItem { favourites }
    }

    private var gridLayoutButton: some View {
        Button("", systemImage: viewModel.grid.otherIcon) {
            withAnimation(.bouncy(duration: 0.25)) { viewModel.grid.toggle() }
        }
    }

    private var favourites: some View {
        Button("", systemImage: Tabs.favourites.icon) {
            viewModel.openFavourites.toggle()
        }
    }

    private var sortTypeBinding: Binding<SortType> {
        Binding(
            get: { viewModel.sortType },
            set: { newType in
                viewModel.sortType = newType
                viewModel.sortDirection = newType.defaultDirection
            }
        )
    }

    private var sortMenu: some View {
        Menu {
            Button(viewModel.sortDirection.label, systemImage: viewModel.sortDirection.systemImage) {
                viewModel.sortDirection.toggle()
            }

            Divider()

            Picker(selection: sortTypeBinding) {
                ForEach(SortType.allCases, id: \.self) { type in
                    Label(type.title, systemImage: type.systemImage)
                        .tag(type)
                }
            } label: {
                Text("Sort by")
            }
        } label: {
            Image(systemName: "arrow.up.and.down.text.horizontal")
        }
    }
}

#Preview {
    @Previewable
    @Environment(\.modelContext) var modelContext

    var vm = PokedexViewModel(modelContext: modelContext, container: .live)
    RootTabView(viewModel: vm)
}
