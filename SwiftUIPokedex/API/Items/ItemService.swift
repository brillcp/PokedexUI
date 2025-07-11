import Networking

struct ItemServiceConfig: ServiceConfiguration, Sendable {
    typealias DetailResponse = ItemDetails
    typealias OutputModel = ItemData

    func createListRequest(lastResponse: APIResponse?) -> Requestable {
        guard let lastResponse,
              let parameters = try? lastResponse.next.asURL().queryParameters()
        else { return ItemRequest.items(limit: 420) }

        let parameterKey = ItemRequest.ParameterKey.self
        let offset = parameters[parameterKey.offset.rawValue] ?? ""
        let limit = parameters[parameterKey.limit.rawValue] ?? "420"
        return ItemRequest.next(offset: offset, limit: limit)
    }

    func createDetailRequest(from urlComponent: String) -> Requestable {
        ItemDetailsRequest.item(urlComponent)
    }

    func transformDetails(_ details: [ItemDetails]) -> [ItemData] {
        let organizedItems = details.reduce([String: [ItemDetails]]()) { itemsDict, item -> [String: [ItemDetails]] in
            var itemsDict = itemsDict
            let items = details.filter { $0.category.name == item.category.name }.sorted(by: { $0.name < $1.name })
            itemsDict[item.category.name] = items
            return itemsDict
        }
        let categories = organizedItems.sorted(by: { $0.key < $1.key }).map { ItemData(title: $0.key, items: $0.value) }
        return categories
    }
}

// MARK: -
final class ItemServiceV2 {
    private let service = APIService(config: ItemServiceConfig())

    func requestItems() async throws -> [ItemData] {
        try await service.requestData()
    }

    func requestNextItems() async throws -> [ItemData] {
        guard await service.hasMore() else { throw APIError.noMoreData }
        return try await service.requestData()
    }

    func hasMoreItems() async -> Bool {
        await service.hasMore()
    }
}
