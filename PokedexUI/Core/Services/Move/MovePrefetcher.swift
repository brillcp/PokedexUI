import Foundation
import SwiftData

/// Downloads every move from PokeAPI once and persists each as a `MoveDetail`
/// row in SwiftData. After the first successful run, battle preflight becomes
/// a pure local query. Runs at `.background` priority.
protocol MovePrefetching: Sendable {
    /// Wire SwiftData storage and kick off the prefetch. Idempotent.
    func warmUp(modelContainer: ModelContainer) async
}

final actor MovePrefetcher {
    private let moveService: MoveServiceProtocol
    private var storage: DataStorageReader?
    private var isLoading = false
    private(set) var isComplete: Bool = false

    init(moveService: MoveServiceProtocol = MoveService()) {
        self.moveService = moveService
    }
}

// MARK: - MovePrefetching

extension MovePrefetcher: MovePrefetching {
    func warmUp(modelContainer: ModelContainer) async {
        attach(modelContainer: modelContainer)
        await prefetchIfNeeded()
    }
}

private extension MovePrefetcher {
    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

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

            let chunkSize = 25
            for chunkStart in stride(from: 0, to: missing.count, by: chunkSize) {
                let chunk = Array(missing[chunkStart..<min(chunkStart + chunkSize, missing.count)])
                do {
                    let details = try await moveService.requestMoves(named: chunk)
                    try await storage.store(details)
                } catch {
                    print("MovePrefetcher: chunk failed at \(chunkStart): \(error)")
                }
            }
            isComplete = true
        } catch {
            print("MovePrefetcher: prefetch failed: \(error)")
        }
    }
}
