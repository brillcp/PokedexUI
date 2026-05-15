import Foundation
import SwiftData
import UIKit

/// Walks every `PokemonSummary` missing a `colorHex`, downloads its front
/// sprite, runs the image color analyzer, and persists the dominant hex back
/// onto the summary row. Runs once at app start after the pokedex grid's
/// pagination loop completes, so by the time the user taps any pokemon the
/// detail view's gradient color is already on disk so it renders frame 1
/// with no black flash.
///
/// Throttled to 6 concurrent pipelines so we don't saturate the network or
/// the GPU during pixel sampling. SpriteLoader's underlying `URLCache` makes
/// repeated runs free: sprites the user already scrolled past in the grid
/// are warm.
final actor SpriteColorPrefetcher {
    private let spriteLoader: SpriteLoader
    private let imageColorAnalyzer: ImageColorAnalyzer
    private var storage: DataStorageReader?
    private var isRunning = false
    private(set) var isComplete = false

    init(spriteLoader: SpriteLoader, imageColorAnalyzer: ImageColorAnalyzer) {
        self.spriteLoader = spriteLoader
        self.imageColorAnalyzer = imageColorAnalyzer
    }

    /// Wire SwiftData storage. Call once during app startup with the shared container.
    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

    /// One-shot prefetch. Iterates the summaries currently in SwiftData,
    /// processes any without a `colorHex`, persists results in batches so a
    /// crash mid-flight isn't a total loss. Safe to call multiple times;
    /// guarded by `isRunning` + `isComplete`.
    func prefetchIfNeeded() async {
        guard !isRunning, !isComplete else { return }
        guard let storage else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            // We need raw ids + sprite URLs to do the analysis off the main
            // actor; collect them as a Sendable snapshot up front, then hand
            // off to the cooperative pool.
            let targets: [Target] = try await storage.fetch(sortBy: SortDescriptor<PokemonSummary>(\.id))
                .compactMap { summary in
                    guard summary.colorHex == nil else { return nil }
                    return Target(id: summary.id, spriteURL: summary.frontSprite)
                }
            guard !targets.isEmpty else {
                isComplete = true
                return
            }

            // Process in chunks of 6 so we never have more than that many
            // sprite downloads + decode + pixel scans in flight at once.
            let chunkSize = 6
            for chunkStart in stride(from: 0, to: targets.count, by: chunkSize) {
                let chunk = Array(targets[chunkStart..<min(chunkStart + chunkSize, targets.count)])
                await withTaskGroup(of: (Int, String?).self) { group in
                    for target in chunk {
                        group.addTask { [spriteLoader, imageColorAnalyzer] in
                            guard let image = await spriteLoader.spriteImage(from: target.spriteURL),
                                  let color = await imageColorAnalyzer.dominantColor(for: target.id, image: image)
                            else {
                                return (target.id, nil)
                            }
                            return (target.id, color.hexString)
                        }
                    }
                    var results: [(Int, String)] = []
                    for await (id, hex) in group {
                        if let hex { results.append((id, hex)) }
                    }
                    if !results.isEmpty {
                        try? await storage.applyColorHexes(results)
                    }
                }
            }
            isComplete = true
        } catch {
            print("SpriteColorPrefetcher: failed: \(error)")
        }
    }

    /// Plain Sendable struct so the cooperative task group doesn't have to
    /// hold a `@Model` ref across actor boundaries.
    private struct Target: Sendable {
        let id: Int
        let spriteURL: String
    }
}
