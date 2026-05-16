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

// MARK: - IdentifiedDataFetcher

/// Cache-first single-entity fetcher. The by-id sibling of `DataFetcher`: same
/// design (storage primitives + API primitives + transforms + a default
/// extension that wires them together), but oriented at a single keyed
/// record instead of a whole list.
///
/// Conformers describe how to look up one row by id, how to fetch it from the
/// network, and how to translate between the storage shape and the
/// presentation shape. The default `fetch(id:)` extension method runs the
/// cache-or-API dance so each call site stays one line.
///
/// Why three associated types: many cache flows use the same Swift type for
/// `StoredData`, `APIData`, and `ViewModel` (e.g. a `@Model` row returned
/// directly by the network layer); separating them gives flows that don't
/// (e.g. a JSON blob persisted as `Data` and decoded on read) a place to
/// declare their boundaries explicitly.
protocol IdentifiedDataFetcher<Identifier, ViewModel> {
    /// Lookup key. Usually `Int` for pokedex ids, `String` for url-encoded
    /// chain ids.
    associatedtype Identifier: Hashable
    /// Shape persisted on disk (often a `@Model` row).
    associatedtype StoredData
    /// Shape returned by the network layer.
    associatedtype APIData
    /// Shape consumed by callers.
    associatedtype ViewModel

    /// Cache lookup. Returns `nil` on miss; throws only on real storage
    /// failure (corrupted DB, schema mismatch).
    func fetchStored(id: Identifier) async throws -> StoredData?
    /// Network fetch. Always hits the wire.
    func fetchAPI(id: Identifier) async throws -> APIData
    /// Persist a freshly-transformed storage row.
    func store(_ data: StoredData) async throws
    /// Map a storage row to the caller-facing view shape.
    func transformToViewModel(_ data: StoredData) -> ViewModel
    /// Map a freshly-fetched API payload to its storage shape. The id is
    /// passed alongside the payload because many wire formats omit it
    /// (e.g. an evolution chain blob keyed externally by url path).
    func transformForStorage(_ data: APIData, id: Identifier) -> StoredData
}

// MARK: - Default implementation

extension IdentifiedDataFetcher {
    /// One-shot cache-or-API dance: return the cached row if present,
    /// otherwise fetch from the network, persist, and return. Logs and
    /// returns `nil` on terminal failure.
    func fetch(id: Identifier) async -> ViewModel? {
        if let cached = try? await fetchStored(id: id) {
            return transformToViewModel(cached)
        }
        do {
            let api = try await fetchAPI(id: id)
            let stored = transformForStorage(api, id: id)
            try? await store(stored)
            return transformToViewModel(stored)
        } catch {
            print("IdentifiedDataFetcher failed for id=\(id): \(error)")
            return nil
        }
    }
}

// MARK: - PaginatedDataFetcher

/// Cache-first paginated fetcher. The third sibling in the family: same
/// design language as `DataFetcher` and `IdentifiedDataFetcher`, but tuned
/// at walking a remote list one page at a time while persisting each batch
/// as it lands so partial walks aren't lost.
///
/// Conformers describe how to read the cached set, fetch one page of API
/// data by offset, dedupe by `Identifier`, and translate between layers. A
/// `syncedFullyKey` (`UserDefaults`) records whether the previous walk
/// reached the end of the remote list; once set, subsequent launches skip
/// the network entirely when the cache is non-empty.
///
/// The default `paginatedLoad()` extension method exposes batches as an
/// `AsyncStream`: the first yield is the cached set (possibly empty),
/// followed by one yield per network page as fresh rows arrive. Callers
/// `for await` the stream and append, keeping the UI progressive.
protocol PaginatedDataFetcher<ViewModel> {
    /// Lookup key used to dedupe across the cache and incoming pages.
    associatedtype Identifier: Hashable
    /// Shape persisted on disk.
    associatedtype StoredData
    /// Shape returned by the network layer.
    associatedtype APIData
    /// Shape consumed by callers.
    associatedtype ViewModel

    /// Page size passed to the remote endpoint.
    var pageSize: Int { get }
    /// `UserDefaults` key flipped to `true` once a clean walk to the empty
    /// page completes. Bump (e.g. suffix `v2`) when the remote list grows
    /// and you need to re-sync.
    var syncedFullyKey: String { get }

    /// Full cached set in display order.
    func fetchStoredData() async throws -> [StoredData]
    /// One page of API rows. Return an empty array to signal exhaustion.
    func fetchAPIPage(offset: Int, limit: Int) async throws -> [APIData]
    /// Persist freshly-transformed storage rows.
    func storeData(_ data: [StoredData]) async throws

    /// Map a storage row to the caller-facing view shape.
    func transformToViewModel(_ data: StoredData) -> ViewModel
    /// Map a wire row to its storage shape.
    func transformForStorage(_ data: APIData) -> StoredData

    /// Identifier of a network row, used to dedupe against the cache.
    func identifier(of data: APIData) -> Identifier
    /// Identifier of a stored row, used to seed the dedup set on resume.
    func identifier(ofStored data: StoredData) -> Identifier
}

// MARK: - Default implementation

extension PaginatedDataFetcher {
    /// `true` once the last walk reached the empty page. Mid-walk failures
    /// leave the flag unset so the next launch retries.
    var isSyncedFully: Bool {
        UserDefaults.standard.bool(forKey: syncedFullyKey)
    }

    /// Record that the remote list has been walked end-to-end. Subsequent
    /// launches will trust the cache and skip the network.
    func markSyncedFully() {
        UserDefaults.standard.set(true, forKey: syncedFullyKey)
    }

    /// Progressive load: yields the cached set first (possibly empty), then
    /// each network page as fresh rows arrive. Skips the network entirely
    /// when the cache is non-empty and `isSyncedFully` is `true`.
    ///
    /// Callers `for await` the stream and append; the stream finishes on
    /// natural exhaustion (empty page) or terminal error.
    func paginatedLoad() -> AsyncStream<[ViewModel]> {
        AsyncStream { continuation in
            Task {
                let cached = (try? await fetchStoredData()) ?? []
                continuation.yield(cached.map(transformToViewModel))

                if !cached.isEmpty, isSyncedFully {
                    continuation.finish()
                    return
                }

                var offset = cached.count
                var knownIds = Set(cached.map(identifier(ofStored:)))
                var exhausted = false

                while true {
                    do {
                        let page = try await fetchAPIPage(offset: offset, limit: pageSize)
                        if page.isEmpty {
                            exhausted = true
                            break
                        }
                        let fresh = page.filter { !knownIds.contains(identifier(of: $0)) }
                        if !fresh.isEmpty {
                            let stored = fresh.map(transformForStorage)
                            try? await storeData(stored)
                            knownIds.formUnion(stored.map(identifier(ofStored:)))
                            continuation.yield(stored.map(transformToViewModel))
                        }
                        offset += page.count
                    } catch {
                        print("PaginatedDataFetcher page failed at offset \(offset): \(error)")
                        break
                    }
                }
                if exhausted { markSyncedFully() }
                continuation.finish()
            }
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
