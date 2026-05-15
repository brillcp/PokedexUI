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
            PokemonSummary.self,
            Pokemon.self,
            ItemData.self,
            TypeDetail.self,
            MoveDetail.self
        ])
    }
}

// MARK: - Root view

/// Hosts the `PokedexView` and kicks off every one-shot bootstrap task at
/// app launch: type chart hydration, bulk move prefetch, sprite color
/// prefetch. All three early-return on subsequent launches once their cache
/// is full.
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
            // One-shot bulk move download. Mirrors `TypeChartLoader.loadIfNeeded`
            // semantics: first launch fetches ~900 moves at background priority,
            // subsequent launches see the cache and early-return without any
            // network hit. Battle preflight reads `MoveDetail` rows locally.
            container.movePrefetcher.attach(modelContainer: modelContext.container)
            await container.movePrefetcher.prefetchIfNeeded()
        }
        .task(priority: .background) {
            await container.spriteColorPrefetcher.attach(modelContainer: modelContext.container)
            await container.spriteColorPrefetcher.prefetchIfNeeded()
        }
    }
}
