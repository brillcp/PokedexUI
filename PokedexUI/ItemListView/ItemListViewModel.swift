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
    /// Service responsible for fetching items.
    private let itemService: ItemServiceProtocol
    private let storage: DataStorageReader

    /// The list of items currently displayed to the user.
    var items: [ItemData] = []

    /// Indicates whether a data request is in progress.
    var isLoading: Bool = false

    /// Initializes a new instance of `ItemsListViewModel` with an optional item service.
    /// - Parameter itemService: The service used to fetch items. Defaults to a new `ItemService`.
    init(modelContext: ModelContext, itemService: ItemService = ItemService()) {
        self.itemService = itemService
        self.storage = DataStorageReader(modelContainer: modelContext.container)
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
            await fetchDataFromStorageOrAPI()
        }
    }
}

// MARK: - DataFetcher implementation
extension ItemListViewModel: DataFetcher {
    typealias StoredData = ItemData
    typealias APIData = ItemData
    typealias ViewModel = ItemData

    func fetchStoredData() async throws -> [StoredData] {
        try await storage.fetch(sortBy: SortDescriptor(\.title)) { $0 }
    }

    func fetchAPIData() async throws -> [APIData] {
        try await itemService.requestItems()
    }

    func storeData(_ data: [StoredData]) async throws {
        try await storage.store(data)
    }

    func transformToViewModel(_ data: StoredData) -> ViewModel {
        ViewModel(title: data.title, items: data.items)
    }

    func transformForStorage(_ data: ViewModel) -> StoredData {
        data
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
