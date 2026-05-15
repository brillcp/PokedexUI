import Foundation
import SwiftData

/// Loads the 18 type damage relations once per app install. Snapshots the
/// SwiftData rows into a Sendable `TypeChart` value the moment they land —
/// downstream consumers (`BattleAIService`, `BattleEngine`, AI prompt builder)
/// then read that value off-main without any actor hop.
///
/// Stays `@MainActor @Observable` because SwiftUI views (`WeaknessGridView`)
/// still bind to its `chart` property directly. Off-main consumers grab
/// `chart` once on entry and pass the captured value by parameter.
@MainActor
@Observable
final class TypeChartLoader {
    private let typeService: TypeServiceProtocol
    private var storage: DataStorageReader?
    private var isLoading = false

    /// Sendable snapshot. `nil` until the first successful load — views guard
    /// on this and render nothing until populated.
    private(set) var chart: TypeChart?

    nonisolated init(typeService: TypeServiceProtocol = TypeService()) {
        self.typeService = typeService
    }

    /// Wire SwiftData storage. Call once during app startup with the shared container.
    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

    /// Hydrate from disk if available, otherwise fetch from the API once and persist.
    func loadIfNeeded() async {
        guard !isLoading, chart == nil else { return }
        isLoading = true
        defer { isLoading = false }

        if let cached = try? await storage?.fetch(sortBy: SortDescriptor<TypeDetail>(\.name)),
           !cached.isEmpty {
            chart = TypeChart(rows: cached)
            return
        }

        do {
            let types = try await typeService.requestTypes()
            chart = TypeChart(rows: types)
            try await storage?.store(types)
        } catch {
            print("TypeChartLoader: failed to load — \(error)")
        }
    }

    /// Convenience for SwiftUI views that need a sync lookup on main. Off-main
    /// callers should capture `chart` once and call `chart.multiplier(...)`
    /// directly to avoid the main hop.
    func multiplier(attacking: String, defenders: [String]) -> Double {
        chart?.multiplier(attacking: attacking, defenders: defenders) ?? 1.0
    }
}
