import Networking

protocol ItemServiceProtocol {
    var service: APIService<ItemService.Config> { get }

    func requestItems() async throws -> [ItemData]
}

// MARK: - ItemService implementation
final class ItemService {
    let service: APIService<Config>

    init(service: APIService<Config> = .init(config: Config())) {
        self.service = service
    }
}

// MARK: - ItemServiceProtocol
extension ItemService: ItemServiceProtocol {
    func requestItems() async throws -> [ItemData] {
        try await service.requestData()
    }
}

// MARK: - ItemService configuration
extension ItemService {
    struct Config: ServiceConfiguration {
        typealias ResponseType = ItemDetails
        typealias OutputModel = ItemData

        func createRequest(lastResponse: APIResponse?) -> Requestable {
            guard let lastResponse,
                  let parameters = try? lastResponse.next.asURL().queryParameters()
            else { return ItemRequest.items(limit: 420) }

            let parameterKey = ItemRequest.ParameterKey.self
            let offset = parameters[parameterKey.offset.rawValue] ?? ""
            let limit = parameters[parameterKey.limit.rawValue] ?? "420"
            return ItemRequest.next(offset: offset, limit: limit)
        }

        func createDetailRequest(from urlComponent: String) -> Requestable {
            ItemRequest.details(urlComponent)
        }

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
