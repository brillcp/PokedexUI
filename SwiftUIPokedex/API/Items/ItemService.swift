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
        details.map { ItemData(title: $0.name, items: []) }
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
