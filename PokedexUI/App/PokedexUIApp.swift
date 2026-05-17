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

/// Hosts the `PokedexView` and kicks off bootstrap tasks at app launch:
/// type chart hydration, bulk move prefetch, and species hydration. Each
/// early-returns on subsequent launches once its cache is full.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.container) private var container

    var body: some View {
        PokedexView(
            viewModel: PokedexViewModel(modelContext: modelContext),
            itemListViewModel: ItemListViewModel(modelContext: modelContext)
        )
        .task {
            container.typeChart.attach(modelContainer: modelContext.container)
            await container.typeChart.loadIfNeeded()
        }
        .task(priority: .background) {
            await container.movePrefetcher.attach(modelContainer: modelContext.container)
            await container.movePrefetcher.prefetchIfNeeded()
        }
        .task(priority: .background) {
            await container.pokemonHydrator.attach(modelContainer: modelContext.container)
            await container.pokemonHydrator.hydrateIfNeeded()
        }
    }
}
