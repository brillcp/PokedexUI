import SwiftUI
import SwiftData

@main
struct PokedexUIApp: App {
    var body: some Scene {
        WindowGroup {
            PokedexView(
                viewModel: PokedexViewModel(),
                itemsListViewModel: ItemsListViewModel(),
                searchViewModel: SearchViewModel()
            )
        }
        .modelContainer(for: [BookmarkedPokemon.self])
    }
}
