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

    /// Returns a filtered list of items that match the given query string.
    ///
    /// The search is case- and diacritic-insensitive, and considers both
    /// the item's name and description. Items whose names start with the
    /// query are prioritized in the result.
    ///
    /// - Parameter query: The search term used to filter items.
    /// - Returns: An array of `ItemData` instances matching the query.
    func searchItems(matching query: String) -> [ItemData]
}

// MARK: - ItemService implementation
/// A concrete implementation of `ItemServiceProtocol` for interacting with the item-related endpoints of the PokeAPI.
final class ItemService {
    private var allItems: [ItemData] = []

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
    func requestItems() async throws -> [ItemData] {
        allItems = try await service.requestData()
        return allItems
    }

    func searchItems(matching query: String) -> [ItemData] {
        allItems.filter { $0.items.contains { $0.matches(query: query) } }
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
