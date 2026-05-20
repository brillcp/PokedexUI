import Foundation
import SwiftData
import SwiftUI

/// Observable view model behind the pokedex grid.
@MainActor
protocol PokedexViewModelProtocol {
    /// `true` while fetching is in-flight.
    var isLoading: Bool { get }
    /// 0...1 progress during first-load API fetch.
    var loadingProgress: Double { get }
    /// Currently selected tab in the parent `TabView`.
    var selectedTab: Tabs { get set }
    /// Current pokedex grid layout (3 cols vs 4 cols).
    var grid: GridLayout { get set }
    /// Active sort applied to the grid's `@Query` corpus.
    var sortType: SortType { get set }

    /// Load all Pokemon: cache first, then network if needed.
    func requestPokemon() async
}

/// Live implementation of `PokedexViewModelProtocol`.
@Observable
final class PokedexViewModel {
    private static let totalDownloadUnits: Int = 1024 + 1024 + 540 + 1

    private let fetcher: PokemonFetcher

    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedTab: Tabs = .pokedex
    var grid: GridLayout = .three
    var sortType: SortType = .number

    private var downloadTicks: Int = 0

    init(modelContext: ModelContext, container: AppContainer) {
        self.fetcher = PokemonFetcher(modelContext: modelContext, container: container)
    }
}

extension PokedexViewModel: PokedexViewModelProtocol {
    func requestPokemon() async {
        guard !isLoading else { return }

        if let cached = try? await fetcher.fetchStoredData(), !cached.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }
        resetProgress()
        let tick: @Sendable () async -> Void = { [weak self] in
            await MainActor.run { self?.tickDownload() }
        }

        do {
            let bootstrap = try await fetcher.fetchBootstrap(onTick: tick)
            try await fetcher.persist(bootstrap)
        } catch {
            print("PokedexViewModel: fetch failed: \(error)")
        }
    }
}

private extension PokedexViewModel {
    func resetProgress() {
        downloadTicks = 0
        loadingProgress = 0
    }

    func tickDownload() {
        downloadTicks += 1
        loadingProgress = min(1.0, Double(downloadTicks) / Double(Self.totalDownloadUnits))
    }
}
