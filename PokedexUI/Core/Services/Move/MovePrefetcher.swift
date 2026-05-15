import Foundation
import SwiftData

/// Downloads every move from PokeAPI once and persists each as a `MoveDetail`
/// row in SwiftData. Move data is effectively static (power/accuracy/type don't
/// change between Pokémon generations within the same game id), so after the
/// first successful run on a device we never hit the network for moves again —
/// battle preflight becomes a pure local query.
///
/// Background worker — no SwiftUI binding, no main-actor isolation. Runs on
/// the cooperative thread pool at `.background` priority so it doesn't fight
/// the pokedex paginated loader for cycles.
final actor MovePrefetcher {
    private let moveService: MoveServiceProtocol
    private var storage: DataStorageReader?
    private var isLoading = false

    /// `true` once every known move name has a persisted `MoveDetail` row.
    /// Surfaced for UI ("Battle ready" badge etc.) if needed later — battles
    /// don't actually wait on this flag (they fall back to per-move fetches
    /// for any names not yet persisted).
    private(set) var isComplete: Bool = false

    init(moveService: MoveServiceProtocol = MoveService()) {
        self.moveService = moveService
    }

    /// Wire SwiftData storage. Call once during app startup with the shared container.
    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

    /// One-shot prefetch. Safe to call repeatedly — the first invocation drives
    /// the download, subsequent calls early-return.
    ///
    /// Flow:
    /// 1. Fetch the cached `MoveDetail` rows currently on disk.
    /// 2. Ask PokeAPI for the full list of move names (`/move?limit=2000`).
    /// 3. Diff to find missing names.
    /// 4. Download missing in chunks of 25 (so we don't open 900 sockets at once).
    /// 5. Persist after each chunk so a crash mid-flight isn't a total loss.
    func prefetchIfNeeded() async {
        guard !isLoading, !isComplete else { return }
        guard let storage else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let cached: [MoveDetail] = try await storage.fetch(sortBy: SortDescriptor<MoveDetail>(\.name))
            let cachedNames = Set(cached.map(\.name))

            let allNames = try await moveService.requestAllMoveNames()
            let missing = allNames.filter { !cachedNames.contains($0) }

            if missing.isEmpty {
                isComplete = true
                return
            }

            // Chunk by 25 so we don't blast PokeAPI with ~900 simultaneous connections.
            let chunkSize = 25
            for chunkStart in stride(from: 0, to: missing.count, by: chunkSize) {
                let chunk = Array(missing[chunkStart..<min(chunkStart + chunkSize, missing.count)])
                do {
                    let details = try await moveService.requestMoves(named: chunk)
                    try await storage.store(details)
                } catch {
                    // Soft-fail per chunk so one bad move name doesn't abort the
                    // whole prefetch. Next launch retries the gaps.
                    print("MovePrefetcher: chunk failed at \(chunkStart): \(error)")
                }
            }
            isComplete = true
        } catch {
            print("MovePrefetcher: prefetch failed — \(error)")
        }
    }
}
