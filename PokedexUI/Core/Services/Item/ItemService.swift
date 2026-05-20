import Foundation
import Networking
import SwiftData

/// Interface for fetching item data from PokeAPI.
protocol ItemServiceProtocol {
    /// Fetch all categorized item data.
    func requestItems() async throws -> [ItemData]
}

/// Default `APIService`-backed implementation.
final class ItemService {
    private let service: APIService<Config>

    init(service: APIService<Config> = .init(config: Config())) {
        self.service = service
    }
}

extension ItemService: ItemServiceProtocol {
    func requestItems() async throws -> [ItemData] {
        try await service.requestData()
    }
}

extension ItemService {
    struct Config: ServiceConfiguration {
        typealias ResponseType = ItemDetail & Sendable
        typealias OutputModel = ItemData

        func createRequest() -> Requestable {
            ItemRequest.items(limit: 2048)
        }

        func createDetailRequest(from urlComponent: String) -> Requestable {
            ItemRequest.details(urlComponent)
        }

        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            let withSprites = response.filter { $0.sprites?.default != nil }
            return Dictionary(grouping: withSprites, by: { $0.category.name })
                .sorted(by: { $0.key < $1.key })
                .map { ItemData(title: $0.key, items: $0.value) }
        }
    }
}

// MARK: - ItemFetcher

/// `DataFetcher` conformer for the items list.
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

    func shouldInvalidate(_ stored: [ItemData]) -> Bool {
        stored.contains(where: { $0.prettyTitle.isEmpty })
    }

    func clearStoredData() async throws {
        await storage.clear(ItemData.self)
        await storage.clear(ItemDetail.self)
        await storage.clear(Effect.self)
    }
}
