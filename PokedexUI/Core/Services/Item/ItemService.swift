import Foundation
import Networking
import SwiftData

/// A protocol defining the interface for fetching item data.
protocol ItemServiceProtocol {
    /// The underlying API service used to fetch and decode item data.
    var service: APIService<ItemService.Config> { get }

    /// Requests a list of categorized item data.
    ///
    /// - Returns: An array of `ItemData` grouped by category.
    /// - Throws: An error if the request or decoding fails.
    func requestItems() async throws -> [ItemData]
}

// MARK: - ItemService implementation
/// A concrete implementation of `ItemServiceProtocol` for interacting with the item-related endpoints of the PokeAPI.
final class ItemService {
    /// The underlying generic API service responsible for data fetching.
    let service: APIService<Config>

    /// Creates a new `ItemService` instance with an optional custom API service.
    ///
    /// - Parameter service: A configured API service. Defaults to a service using `ItemService.Config`.
    init(service: APIService<Config> = .init(config: Config())) {
        self.service = service
    }
}

// MARK: - ItemServiceProtocol
extension ItemService: ItemServiceProtocol {
    /// Requests and loads all available item data from the API.
    ///
    /// This method performs an asynchronous fetch using the underlying `APIService` to retrieve all item details,
    /// storing the result locally in `allItems` for later querying. The returned array is grouped by category and sorted as defined by the API configuration.
    ///
    /// - Returns: An array of `ItemData` containing all categorized items fetched from the API.
    /// - Throws: Any error encountered during the network request or data decoding process.
    func requestItems() async throws -> [ItemData] {
        try await service.requestData()
    }
}

// MARK: - ItemService configuration
extension ItemService {
    /// A configuration used by `APIService` to define item-specific requests and response transformation.
    struct Config: ServiceConfiguration {
        typealias ResponseType = ItemDetail & Sendable
        typealias OutputModel = ItemData

        /// Builds the request used to fetch the complete list of item summaries.
        ///
        /// - Returns: A `Requestable` representing the item list request.
        func createRequest() -> Requestable {
            ItemRequest.items(limit: 2048)
        }

        /// Builds a request for fetching detailed information about a single item.
        ///
        /// - Parameter urlComponent: The last path component of the item detail URL.
        /// - Returns: A `Requestable` representing the item detail request.
        func createDetailRequest(from urlComponent: String) -> Requestable {
            ItemRequest.details(urlComponent)
        }

        /// Transforms an array of item details into grouped `ItemData` models.
        /// Categories are sorted alphabetically by title. Items within each category are
        /// sorted at the display layer because SwiftData `@Relationship` arrays do not
        /// preserve order on persistence.
        ///
        /// - Parameter response: The array of detailed item objects.
        /// - Returns: An array of `ItemData` grouped by category, sorted alphabetically by title.
        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            let withSprites = response.filter { $0.sprites?.default != nil }
            return Dictionary(grouping: withSprites, by: { $0.category.name })
                .sorted(by: { $0.key < $1.key })
                .map { ItemData(title: $0.key, items: $0.value) }
        }
    }
}

// MARK: - ItemFetcher

/// `DataFetcher` conformer for the items list. Pulled out of
/// `ItemListViewModel` so the view model is concerned only with UI state
/// (`items`, `isLoading`) while this struct owns the cache-or-API
/// choreography. Composition over conformance: the VM **has** a fetcher
/// rather than **is** a fetcher.
///
/// All three associated types collapse to `ItemData` because the wire
/// payload is decoded straight into the `@Model` row used by the view; a
/// minimal example of `DataFetcher` for cases where no shape translation
/// is needed.
struct ItemFetcher: DataFetcher {
    typealias StoredData = ItemData
    typealias APIData = ItemData
    typealias ViewModel = ItemData

    private let storage: DataStorageReader
    private let service: ItemServiceProtocol

    init(modelContext: ModelContext, container: AppContainer) {
        self.storage = DataStorageReader(modelContainer: modelContext.container)
        self.service = container.itemService
    }

    func fetchStoredData() async throws -> [ItemData] {
        try await storage.fetch(sortBy: SortDescriptor(\.title))
    }

    func fetchAPIData() async throws -> [ItemData] {
        try await service.requestItems()
    }

    func storeData(_ data: [ItemData]) async throws {
        try await storage.store(data)
    }

    func transformToViewModel(_ data: ItemData) -> ItemData { data }
    func transformForStorage(_ data: ItemData) -> ItemData { data }

    /// Force a refresh when the local cache predates the response-grouping
    /// fix that filled in `prettyTitle`. Empty titles mark a stale row.
    func shouldInvalidate(_ stored: [ItemData]) -> Bool {
        stored.contains(where: { $0.prettyTitle.isEmpty })
    }

    func clearStoredData() async throws {
        await storage.clear(ItemData.self)
        await storage.clear(ItemDetail.self)
        await storage.clear(Effect.self)
    }
}
