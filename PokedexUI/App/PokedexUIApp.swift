import SwiftUI
import SwiftData

/// App entry point. Registers every `@Model` type with SwiftData and hands
/// `RootView` the model container; everything else is constructed downstream
/// via `AppContainer`.
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

// MARK: - Root view

/// Hosts the `PokedexView`. No background workers run at launch; the view
/// model handles the full fetch-store-display cycle.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.container) private var container

    var body: some View {
        PokedexView(
            viewModel: PokedexViewModel(
                modelContext: modelContext,
                container: container
            ),
            itemListViewModel: ItemListViewModel(modelContext: modelContext)
        )
    }
}
