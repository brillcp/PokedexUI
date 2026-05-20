import Foundation
import SwiftData

/// Loads the 18 type damage relations once per app install. Snapshots
/// SwiftData rows into a Sendable `TypeChart` for off-main consumers.
/// `@Observable` so SwiftUI views can bind to `chart` synchronously.
@Observable
final class TypeChartLoader {
    private let typeService: TypeServiceProtocol
    private var storage: DataStorageReader?
    private var isLoading = false

    private(set) var chart: TypeChart?

    init(typeService: TypeServiceProtocol = TypeService()) {
        self.typeService = typeService
    }

    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

    func warmUp(modelContainer: ModelContainer, onTick: (@Sendable () async -> Void)? = nil) async {
        attach(modelContainer: modelContainer)
        await loadIfNeeded()
        await onTick?()
    }

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
            print("TypeChartLoader: failed to load: \(error)")
        }
    }

    func multiplier(attacking: String, defenders: [String]) -> Double {
        chart?.multiplier(attacking: attacking, defenders: defenders) ?? 1.0
    }
}
