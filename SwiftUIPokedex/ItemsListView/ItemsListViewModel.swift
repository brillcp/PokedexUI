import Foundation

/// Protocol defining an observable view model that manages a list of items and supports searching.
protocol ItemsListViewModelProtocol: ObservableObject {
    /// The current list of items being displayed.
    var items: [ItemData] { get }
    
    /// The current search query string.
    var query: String { get set }

    /// Loads all items asynchronously from the data source.
    func loadItems() async
    
    /// Performs a search on the items based on the current query.
    func search() async
    
    /// Clears the search results when the search query changes from a non-empty to an empty string.
    /// - Parameters:
    ///   - oldValue: The previous search query.
    ///   - newValue: The new search query.
    func clearSearch(_ oldValue: String, _ newValue: String)
}

// MARK: -
/// View model that manages the retrieval, searching, and storage of items.
final class ItemsListViewModel {
    /// Service responsible for fetching items.
    private let itemService: ItemServiceProtocol
    
    /// Complete list of all items fetched.
    private var allItems: [ItemData] = []

    /// The list of items currently displayed to the user.
    @Published var items: [ItemData] = []
    
    /// The current search query entered by the user.
    @Published var query: String = ""

    /// Initializes a new instance of `ItemsListViewModel` with an optional item service.
    /// - Parameter itemService: The service used to fetch items. Defaults to a new `ItemService`.
    init(itemService: ItemService = ItemService()) {
        self.itemService = itemService
    }
}

// MARK: - ItemsListViewModelProtocol
extension ItemsListViewModel: ItemsListViewModelProtocol {
    /// Loads all items from the item service asynchronously.
    /// Does nothing if items have already been loaded.
    @MainActor
    func loadItems() async {
        guard items.isEmpty else { return }

        do {
            let data = try await itemService.requestItems()
            allItems = data
            items = data
        } catch {
            print(error.localizedDescription)
        }
    }

    /// Performs a search based on the current search query.
    /// If the query is empty, resets the items to the full list.
    /// Loads items first if they have not been loaded yet.
    @MainActor
    func search() async {
        guard !query.isEmpty else {
            items = allItems
            return
        }

        if allItems.isEmpty {
            await loadItems()
        }

        items = itemService.searchItems(matching: query)
    }

    /// Clears the search results when the search query becomes empty.
    /// - Parameters:
    ///   - oldValue: The previous search query.
    ///   - newValue: The new search query.
    func clearSearch(_ oldValue: String, _ newValue: String) {
        guard newValue.isEmpty else { return }
        items = allItems
    }
}
