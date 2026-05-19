import Foundation
import SwiftData
import SwiftUI

/// Observable view model behind the pokedex grid.
@MainActor
protocol PokedexViewModelProtocol {
    /// The grid's data source.
    var pokemonData: [Pokemon] { get }
    /// `true` while fetching is in-flight.
    var isLoading: Bool { get }
    /// 0...1 progress during first-load API fetch.
    var loadingProgress: Double { get }
    /// Currently selected tab in the parent `TabView`.
    var selectedTab: Tabs { get set }
    /// Current pokedex grid layout (3 cols vs 4 cols).
    var grid: GridLayout { get set }

    /// Load all Pokemon: cache first, then network if needed.
    func requestPokemon() async
    /// Re-sort the in-memory array.
    func sort(by type: SortType) async
}

// MARK: - Implementation

/// Live implementation of `PokedexViewModelProtocol`. Cache-first. All
/// storage and network calls go through a `PokemonFetcher` (a `DataFetcher`
/// conformer), mirroring the `ItemFetcher` pattern used by the items tab.
/// The view model only owns UI state + the shared progress counter; the
/// multi-phase orchestration lives on the fetcher.
@Observable
final class PokedexViewModel {
    /// Hardcoded denominator for the download progress bar. Sums the
    /// expected unit count across every step:
    /// * detail requests (~1024)
    /// * species requests (~1024)
    /// * evolution chains   (~540)
    /// * type chart batch   (1)
    /// PokeAPI's corpus is stable enough that a static estimate is fine;
    /// the bar is clamped at 1.0 so minor drift doesn't matter.
    private static let totalDownloadUnits: Int = 1024 + 1024 + 540 + 1

    private let fetcher: PokemonFetcher

    var pokemonData: [Pokemon] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedTab: Tabs = .pokedex
    var grid: GridLayout = .three

    /// Shared counter that every service ticks through the fetcher.
    /// Aggregate is the raw ratio against `totalDownloadUnits`; no
    /// per-phase weights, no per-phase denominators that could shift
    /// mid-flight.
    private var downloadTicks: Int = 0

    init(modelContext: ModelContext, container: AppContainer) {
        self.fetcher = PokemonFetcher(modelContext: modelContext, container: container)
    }
}

// MARK: - PokedexViewModelProtocol

extension PokedexViewModel: PokedexViewModelProtocol {
    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if let cached = try? await fetcher.fetchStoredData(), !cached.isEmpty {
            pokemonData = cached
            return
        }

        resetProgress()
        let tick: @Sendable () async -> Void = { [weak self] in
            await MainActor.run { self?.tickDownload() }
        }

        do {
            let bootstrap = try await fetcher.downloadEverything(onTick: tick)
            // Force the bar to exactly 1.0 in case estimates were slightly
            // off, then run all persists in one closing step. Spinner
            // takes over because `loadingProgress >= 1.0`.
            loadingProgress = 1.0
            try await fetcher.persist(bootstrap)
            pokemonData = bootstrap.pokemon
        } catch {
            print("PokedexViewModel: fetch failed: \(error)")
        }
    }

    func sort(by type: SortType) async {
        let sorted: [Pokemon] = await Task(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.pokemonData.sorted(by: type.comparator)
        }.value
        withAnimation(.snappy(duration: 0.25)) { pokemonData = sorted }
    }
}

// MARK: - Private

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
