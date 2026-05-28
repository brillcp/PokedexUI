import Foundation
import SwiftData

/// Abstracts fetching data from persistent storage and remote APIs
/// with a cache-first strategy.
protocol DataFetcher {
    associatedtype Model

    /// Fetch all items from persistent storage.
    func fetchStoredData() async throws -> [Model]
    /// Fetch all items from the remote API.
    func fetchAPIData() async throws -> [Model]
    /// Persist an array of items.
    func storeData(_ data: [Model]) async throws
}

extension DataFetcher {
    /// Return cached data when available, otherwise fetch from API and persist.
    func fetchDataFromStorageOrAPI() async -> [Model] {
        if let cached = try? await fetchStoredData(), !cached.isEmpty {
            return cached
        }
        do {
            let data = try await fetchAPIData()
            try await storeData(data)
            return data
        } catch {
            #if DEBUG
            print("API request failed: \(error)")
            #endif
            return []
        }
    }
}
