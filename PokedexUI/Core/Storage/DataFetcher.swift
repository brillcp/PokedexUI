import Foundation
import SwiftData

/// Abstracts fetching data from persistent storage and remote APIs,
/// transforming as needed for local storage and presentation.
protocol DataFetcher {
    associatedtype StoredData
    associatedtype APIData
    associatedtype ViewModel where ViewModel == APIData

    /// Fetch all items from persistent storage.
    func fetchStoredData() async throws -> [StoredData]
    /// Fetch all items from the remote API.
    func fetchAPIData() async throws -> [APIData]
    /// Persist an array of items.
    func storeData(_ data: [StoredData]) async throws
    /// Transform a stored item into a view model.
    func transformToViewModel(_ data: StoredData) -> ViewModel
    /// Transform an API item for local storage.
    func transformForStorage(_ data: APIData) -> StoredData
}

extension DataFetcher {
    func fetchDataFromStorageOrAPI() async -> [ViewModel] {
        if let localData = await fetchStoredDataSafely(),
           !localData.isEmpty {
            return localData.map(transformToViewModel)
        }
        return await fetchDataFromAPI()
    }
}

// MARK: - Private
private extension DataFetcher {
    func fetchStoredDataSafely() async -> [StoredData]? {
        do {
            return try await fetchStoredData()
        } catch {
            print("Failed to fetch stored data: \(error)")
            return nil
        }
    }

    func fetchDataFromAPI() async -> [ViewModel] {
        do {
            let apiData = try await fetchAPIData()
            let storageData = apiData.map(transformForStorage)
            try await storeData(storageData)
            return apiData
        } catch {
            print("API request failed: \(error)")
            return []
        }
    }
}
