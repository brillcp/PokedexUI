import SwiftUI
import SwiftData

/// App entry point.
@main
struct PokedexUIApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Pokemon.self,
            ItemData.self,
            TypeDetail.self,
            MoveDetail.self,
            EvolutionChainEntity.self
        ])
    }
}

/// Root view that wires up the composition root to the main content.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.container) private var container

    var body: some View {
        PokedexView(
            viewModel: PokedexViewModel(
                modelContext: modelContext,
                container: container
            ),
            itemListViewModel: ItemListViewModel(
                modelContext: modelContext,
                container: container
            )
        )
    }
}
