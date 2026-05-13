import Foundation
import SwiftData

/// A protocol that abstracts fetching data from both persistent storage and remote APIs, transforming data as needed for local storage and presentation.
///
/// Types conforming to `DataFetcher` provide a consistent interface for loading, storing, transforming, and presenting data from multiple sources.
protocol DataFetcher {
    /// The concrete type representing items as stored locally (e.g., database model).
    associatedtype StoredData
    /// The concrete type representing items as fetched from a remote API (e.g., DTO).
    associatedtype APIData
    /// The concrete type representing items as presented to the UI (e.g., view model).
    associatedtype ViewModel where ViewModel == APIData

    /// Fetches all items from persistent storage.
    /// - Returns: An array of stored data objects.
    /// - Throws: An error if the fetch fails.
    func fetchStoredData() async throws -> [StoredData]
    /// Fetches all items from the remote API.
    /// - Returns: An array of API data objects.
    /// - Throws: An error if the fetch fails.
    func fetchAPIData() async throws -> [APIData]
    /// Stores an array of items in persistent storage.
    /// - Parameter data: The array of stored data objects to persist.
    /// - Throws: An error if the storage operation fails.
    func storeData(_ data: [StoredData]) async throws
    /// Transforms a stored data object into a presentation-ready view model.
    /// - Parameter data: The stored data object to transform.
    /// - Returns: The corresponding view model.
    func transformToViewModel(_ data: StoredData) -> ViewModel
    /// Transforms an API data object into a type suitable for local storage.
    /// - Parameter data: The API data object to transform.
    /// - Returns: The corresponding stored data object.
    func transformForStorage(_ data: APIData) -> StoredData
    /// Indicates whether the locally stored data should be invalidated and re-fetched
    /// from the API. Defaults to `false`. Override to detect schema migrations or
    /// missing fields that require a refresh.
    func shouldInvalidate(_ stored: [StoredData]) -> Bool
    /// Removes all locally stored data. Defaults to a no-op.
    func clearStoredData() async throws
}

// MARK: - Default Implementation
extension DataFetcher {
    func shouldInvalidate(_ stored: [StoredData]) -> Bool { false }
    func clearStoredData() async throws {}

    /// Fetches data from local storage if available and valid; otherwise, fetches it from the API.
    /// If the cached data fails the `shouldInvalidate` check, storage is cleared before the API call.
    /// - Returns: An array of view models, sourced from storage or API as needed.
    func fetchDataFromStorageOrAPI() async -> [ViewModel] {
        if let localData = await fetchStoredDataSafely(),
           !localData.isEmpty,
           !shouldInvalidate(localData) {
            return localData.map(transformToViewModel)
        }
        try? await clearStoredData()
        return await fetchDataFromAPI()
    }
}

// MARK: - Private functions
private extension DataFetcher {
    /// Attempts to fetch stored data with error handling. Returns nil if fetching fails.
    /// - Returns: An optional array of stored data, or nil if an error occurs.
    func fetchStoredDataSafely() async -> [StoredData]? {
        do {
            return try await fetchStoredData()
        } catch {
            print("Failed to fetch stored data: \(error)")
            return nil
        }
    }

    /// Fetches data from the API, stores it locally, and returns it as view models. Returns an empty array on failure.
    /// - Returns: An array of view models, or an empty array if fetching or storing fails.
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
