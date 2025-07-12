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
    /// Fetches item data by requesting a paginated list from the PokeAPI and resolving detailed item entries.
    ///
    /// - Returns: An array of `ItemData` grouped and sorted by category.
    func requestItems() async throws -> [ItemData] {
        try await service.requestData()
    }
}

// MARK: - ItemService configuration
extension ItemService {
    /// A configuration used by `APIService` to define item-specific requests and response transformation.
    struct Config: ServiceConfiguration {
        typealias ResponseType = ItemDetails
        typealias OutputModel = ItemData

        /// Builds the request used to fetch the next page of item summaries.
        ///
        /// - Parameter lastResponse: The previous paginated API response.
        /// - Returns: A `Requestable` representing the next page or an initial request.
        func createRequest(lastResponse: APIResponse?) -> Requestable {
            guard let lastResponse,
                  let parameters = try? lastResponse.next.asURL().queryParameters()
            else {
                return ItemRequest.items(limit: 420)
            }

            let parameterKey = ItemRequest.ParameterKey.self
            let offset = parameters[parameterKey.offset.rawValue] ?? ""
            let limit = parameters[parameterKey.limit.rawValue] ?? "420"
            return ItemRequest.next(offset: offset, limit: limit)
        }

        /// Builds a request for fetching detailed information about a single item.
        ///
        /// - Parameter urlComponent: The last path component of the item detail URL.
        /// - Returns: A `Requestable` representing the item detail request.
        func createDetailRequest(from urlComponent: String) -> Requestable {
            ItemRequest.details(urlComponent)
        }

        /// Transforms a flat array of item details into grouped and sorted `ItemData` models.
        ///
        /// - Parameter response: The array of detailed item objects.
        /// - Returns: An array of `ItemData`, grouped by category and sorted alphabetically.
        func transformResponse(_ response: [ItemDetails]) -> [ItemData] {
            let grouped = Dictionary(grouping: response, by: { $0.category.name })
                .mapValues { $0.sorted(by: { $0.name < $1.name }) }

            let categories = grouped
                .sorted(by: { $0.key < $1.key })
                .map { ItemData(title: $0.key, items: $0.value) }

            return categories
        }
    }
}
