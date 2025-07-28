import SwiftUI

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
    }
}
