import Foundation
import SwiftData

/// Protocol for an observable view model that manages items and supports searching.
@MainActor
protocol ItemListViewModelProtocol {
    /// The current list of items being displayed.
    var items: [ItemData] { get }
    /// A flag indicating whether data is currently being fetched.
    var isLoading: Bool { get }

    /// Loads all items asynchronously from the data source.
    func loadItems() async
}

/// View model that manages the retrieval, searching, and storage of items.
@Observable
final class ItemListViewModel {
    private let fetcher: ItemFetcher

    var items: [ItemData] = []
    var isLoading: Bool = false

    init(modelContext: ModelContext, container: AppContainer) {
        self.fetcher = ItemFetcher(modelContext: modelContext, container: container)
    }
}

extension ItemListViewModel: ItemListViewModelProtocol {
    @MainActor
    func loadItems() async {
        guard !isLoading, items.isEmpty else { return }

        items = await withLoadingState {
            await fetcher.fetchDataFromStorageOrAPI()
        }
    }
}

private extension ItemListViewModel {
    func withLoadingState<T>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}
