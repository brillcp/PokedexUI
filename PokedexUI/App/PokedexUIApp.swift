import SwiftUI
import SwiftData

@main
struct PokedexUIApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [ItemData.self, Pokemon.self, TypeDetail.self])
    }
}

// MARK: - Root view
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
    }
}
