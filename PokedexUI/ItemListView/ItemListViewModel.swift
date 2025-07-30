import Foundation

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

    /// The list of items currently displayed to the user.
    var items: [ItemData] = []

    /// Indicates whether a data request is in progress.
    var isLoading: Bool = false

    /// Initializes a new instance of `ItemsListViewModel` with an optional item service.
    /// - Parameter itemService: The service used to fetch items. Defaults to a new `ItemService`.
    init(itemService: ItemService = ItemService()) {
        self.itemService = itemService
    }
}

// MARK: - ItemsListViewModelProtocol
extension ItemListViewModel: ItemListViewModelProtocol {
    /// Loads all items from the item service asynchronously.
    /// Does nothing if items have already been loaded.
    @MainActor
    func loadItems() async {
        guard !isLoading, items.isEmpty else { return }
        isLoading.toggle()
        defer { isLoading.toggle() }

        do {
            items = try await itemService.requestItems()
        } catch {
            print(error.localizedDescription)
        }
    }
}
