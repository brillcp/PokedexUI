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
}

// MARK: - Default Implementation
extension DataFetcher {
    /// Fetches data from local storage if available and valid; otherwise, fetches it from the API.
    /// If the cached data fails the `shouldInvalidate` check, storage is cleared before the API call.
    /// - Returns: An array of view models, sourced from storage or API as needed.
    func fetchDataFromStorageOrAPI() async -> [ViewModel] {
        if let localData = await fetchStoredDataSafely(),
           !localData.isEmpty {
            return localData.map(transformToViewModel)
        }
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

// MARK: - BatchDataFetcher

/// Cache-first batch fetcher keyed by an arbitrary `Hashable`. The fourth
/// sibling in the family: same design language as `DataFetcher`,
/// `IdentifiedDataFetcher`, and `PaginatedDataFetcher`, but oriented at a
/// caller-supplied set of keys (e.g. "fetch these 40 move names").
///
/// Conformers describe how to look up rows by key, fetch the missing keys
/// from the network, persist, and translate. The default `fetch(keys:)`
/// extension method runs the cache-or-API dance, preserves the caller's
/// input order, and drops keys that resolved neither from cache nor from
/// the network.
protocol BatchDataFetcher<Key, ViewModel> {
    /// Lookup key. Usually a `String` name or `Int` id.
    associatedtype Key: Hashable
    /// Shape persisted on disk.
    associatedtype StoredData
    /// Shape returned by the network layer.
    associatedtype APIData
    /// Shape consumed by callers.
    associatedtype ViewModel

    /// Cache lookup for the requested keys. Missing keys may be absent
    /// from the returned dictionary; throws only on real storage failure.
    func fetchStored(keys: [Key]) async throws -> [Key: StoredData]
    /// Network fetch for the keys not found in the cache. Implementations
    /// commonly run the batch in parallel under the hood.
    func fetchAPI(missing keys: [Key]) async throws -> [APIData]
    /// Persist freshly-transformed storage rows.
    func store(_ data: [StoredData]) async throws

    /// Map a storage row to the caller-facing view shape.
    func transformToViewModel(_ data: StoredData) -> ViewModel
    /// Map a wire row to its storage shape.
    func transformForStorage(_ data: APIData) -> StoredData

    /// Key carried by a wire row, used to merge the API response with the
    /// cache hits before returning.
    func key(of data: APIData) -> Key
    /// Key carried by a storage row, used to build the cache-hit
    /// dictionary on read.
    func key(ofStored data: StoredData) -> Key
}

// MARK: - Default implementation

extension BatchDataFetcher {
    /// Resolve the requested keys against cache-then-network. Returned
    /// view models follow the caller's input order; keys that resolved
    /// from neither source are dropped silently (the caller decides
    /// whether a partial result is acceptable).
    func fetch(keys: [Key]) async -> [ViewModel] {
        let cached = (try? await fetchStored(keys: keys)) ?? [:]
        let missing = keys.filter { cached[$0] == nil }

        var fetched: [Key: StoredData] = [:]
        if !missing.isEmpty {
            do {
                let api = try await fetchAPI(missing: missing)
                let stored = api.map(transformForStorage)
                try? await store(stored)
                fetched = Dictionary(uniqueKeysWithValues: stored.map { (key(ofStored: $0), $0) })
            } catch {
                print("BatchDataFetcher fetch failed for \(missing.count) keys: \(error)")
            }
        }

        let merged = cached.merging(fetched, uniquingKeysWith: { lhs, _ in lhs })
        return keys.compactMap { merged[$0].map(transformToViewModel) }
    }
}
