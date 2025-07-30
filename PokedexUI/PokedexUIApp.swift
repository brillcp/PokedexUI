import SwiftUI
import SwiftData

@main
struct PokedexUIApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [BookmarkedPokemon.self, Pokemon.self])
    }
}

private struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        PokedexView(
            viewModel: PokedexViewModel(modelContext: modelContext),
            itemsListViewModel: ItemsListViewModel(),
            searchViewModel: SearchViewModel()
        )
    }
}
