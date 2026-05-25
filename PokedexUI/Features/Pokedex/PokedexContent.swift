import SwiftUI

/// Pokedex tab content with grid and toolbar.
struct PokedexContent<ViewModel: PokedexViewModelProtocol>: View {
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
