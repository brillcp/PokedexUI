import Networking

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
            ItemRequest.items(limit: 860)
        }

        /// Builds a request for fetching detailed information about a single item.
        ///
        /// - Parameter urlComponent: The last path component of the item detail URL.
        /// - Returns: A `Requestable` representing the item detail request.
        func createDetailRequest(from urlComponent: String) -> Requestable {
            ItemRequest.details(urlComponent)
        }

        /// Transforms an array of item details into grouped and sorted `ItemData` models.
        ///
        /// - Parameter response: The array of detailed item objects.
        /// - Returns: An array of `ItemData`, grouped by category and sorted alphabetically.
        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            let grouped = Dictionary(grouping: response, by: { $0.category.name })
                .mapValues { $0.sorted(by: { $0.name < $1.name }) }

            let categories = grouped
                .sorted(by: { $0.key < $1.key })
                .map { ItemData(title: $0.key, items: $0.value) }

            return categories
        }
    }
}
