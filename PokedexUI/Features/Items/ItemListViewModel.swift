import Foundation
import SwiftData

/// Protocol defining an observable view model that manages a list of items and supports searching.
@MainActor
protocol ItemListViewModelProtocol {
    /// The current list of items being displayed.
    var items: [ItemData] { get }
    /// A flag indicating whether data is currently being fetched.
    var isLoading: Bool { get }

    /// Loads all items asynchronously from the data source.
    func loadItems() async
}

// MARK: -
/// View model that manages the retrieval, searching, and storage of items.
@Observable
final class ItemListViewModel {
    /// Fetcher that owns the cache-or-API choreography for the items list.
    /// Composition over conformance: the view model **has** a fetcher rather
    /// than **is** a fetcher.
    private let fetcher: ItemFetcher

    /// The list of items currently displayed to the user.
    var items: [ItemData] = []

    /// Indicates whether a data request is in progress.
    var isLoading: Bool = false

    /// - Parameters:
    ///   - modelContext: SwiftData context that backs the `ItemFetcher`'s
    ///     storage reader.
    ///   - container: Composition root the fetcher reads `itemService` from.
    init(modelContext: ModelContext, container: AppContainer) {
        self.fetcher = ItemFetcher(modelContext: modelContext, container: container)
    }
}

// MARK: - ItemsListViewModelProtocol
extension ItemListViewModel: ItemListViewModelProtocol {
    /// Loads all items from the item service asynchronously.
    /// Does nothing if items have already been loaded.
    @MainActor
    func loadItems() async {
        guard !isLoading, items.isEmpty else { return }

        items = await withLoadingState {
            await fetcher.fetchDataFromStorageOrAPI()
        }
    }
}

// MARK: - Private loading function
private extension ItemListViewModel {
    func withLoadingState<T>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}
