/// PokemonDetailViewModel.swift
///
/// Contains the ViewModel and protocol for presenting detailed information about a single Pokémon.
/// Handles sprite and color loading, bookmarking, sprite flipping, and sound playback.

import SwiftUI // Required for Image and Color types
import SwiftData // Required for SwiftData model and context

/// Protocol defining the requirements for a Pokémon detail view model.
/// Provides state and behaviors for displaying and interacting with Pokémon details in the UI.
@MainActor
protocol PokemonDetailViewModelProtocol {
    /// The Pokémon represented by this ViewModel.
    var pokemon: PokemonViewModelProtocol { get }
    /// Indicates whether the Pokémon is currently bookmarked by the user.
    var isBookmarked: Bool { get }
    /// Indicates if the sprite is flipped (showing the back view).
    var isFlipped: Bool { get set }
    /// The image for the Pokémon's front sprite, if loaded.
    var frontSprite: Image? { get }
    /// The image for the Pokémon's back sprite, if loaded.
    var backSprite: Image? { get }
    /// The dominant color extracted from the Pokémon's sprite image, if available.
    var color: Color? { get }

    /// Loads the Pokémon's front and back sprite images and determines the dominant color.
    /// - Parameters:
    ///   - spriteLoader: Helper for loading sprite images asynchronously.
    ///   - imageColorAnalyzer: Helper for extracting the dominant color from an image.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader, imageColorAnalyzer: ImageColorAnalyzer) async
    /// Sets the `isBookmarked` property based on a provided list of bookmarked Pokémon.
    /// - Parameter bookmarks: Array of all bookmarked Pokémon from storage.
    func updateBookmarkStatus(from bookmarks: [Pokemon])
    /// Toggles the bookmark status for this Pokémon in the provided model context.
    /// - Parameter context: The SwiftData model context.
    func toggleBookmark(in context: ModelContext)
    /// Flips the sprite to show the back, with haptic feedback.
    /// - Parameter hapticFeedback: The feedback generator for haptic response.
    func flipSprite(hapticFeedback: UIImpactFeedbackGenerator)
    /// Flips the sprite back to the front, with haptic feedback.
    /// - Parameter hapticFeedback: The feedback generator for haptic response.
    func flipSpriteBack(hapticFeedback: UIImpactFeedbackGenerator)
    /// Plays the Pokémon's cry sound (if available) using an audio player.
    /// - Parameter audioPlayer: The audio player to use for sound playback.
    func playSound(with audioPlayer: AudioPlayer) async
}

/// Observable class that manages detailed UI state and behaviors for a single Pokémon.
@Observable
final class PokemonDetailViewModel {
    // MARK: Public Properties

    /// The Pokémon to display details for.
    let pokemon: PokemonViewModelProtocol
    /// Whether this Pokémon is currently bookmarked.
    var isBookmarked = false
    /// Whether the sprite is currently flipped to the back side.
    var isFlipped = false
    /// The loaded front sprite image.
    var frontSprite: Image?
    /// The loaded back sprite image (optional).
    var backSprite: Image?
    /// The dominant color extracted from the front sprite image.
    var color: Color?

    // MARK: - Initialization
    /// Creates a new ViewModel for the specified Pokémon.
    /// - Parameter pokemon: The Pokémon to represent.
    init(pokemon: PokemonViewModelProtocol) {
        self.pokemon = pokemon
    }
}

// MARK: - PokemonDetailViewModelProtocol
extension PokemonDetailViewModel: PokemonDetailViewModelProtocol {
    /// Updates `isBookmarked` based on whether this Pokémon appears in the provided bookmarks list.
    /// - Parameter bookmarks: The user's list of bookmarked Pokémon entities.
    func updateBookmarkStatus(from bookmarks: [Pokemon]) {
        isBookmarked = bookmarks.contains(where: { $0.id == pokemon.id })
    }

    /// Loads the front sprite, back sprite (if available), and extracts the dominant color from the front sprite.
    /// Updates the `frontSprite`, `backSprite`, and `color` properties.
    /// - Parameters:
    ///   - spriteLoader: Loader to fetch sprite images asynchronously.
    ///   - imageColorAnalyzer: Analyzer to determine the dominant color from an image.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader, imageColorAnalyzer: ImageColorAnalyzer) async {
        guard let image = await spriteLoader.spriteImage(from: pokemon.frontSprite),
              let uicolor = await imageColorAnalyzer.dominantColor(for: pokemon.id, image: image)
        else { return }

        color = Color(uiColor: uicolor)
        frontSprite = Image(uiImage: image)

        if let backSpriteURL = pokemon.backSprite,
           let backImage = await spriteLoader.spriteImage(from: backSpriteURL) {
            backSprite = Image(uiImage: backImage)
        }
    }

    /// Toggles the bookmark status for this Pokémon in the specified model context and updates the view model state.
    /// - Parameter context: The SwiftData model context for persistence.
    func toggleBookmark(in context: ModelContext) {
        let id = pokemon.id
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })

        do {
            if let pokemonEntity = try context.fetch(descriptor).first {
                pokemonEntity.isBookmarked.toggle()
                isBookmarked = pokemonEntity.isBookmarked
                try context.save()
            }
        } catch {
            print("Failed to toggle bookmark: \(error)")
        }
    }

    /// Plays the Pokémon's most recent cry sound if a URL is available, using the provided audio player.
    /// - Parameter audioPlayer: The audio player responsible for playback.
    func playSound(with audioPlayer: AudioPlayer) async {
        guard let cryURL = pokemon.latestCry else { return }
        await audioPlayer.play(from: cryURL)
    }

    /// Flips the sprite to display the back image and triggers haptic feedback if not already flipped.
    /// - Parameter hapticFeedback: The haptic feedback generator.
    func flipSprite(hapticFeedback: UIImpactFeedbackGenerator) {
        guard !isFlipped else { return }
        isFlipped = true
        hapticFeedback.impactOccurred()
    }

    /// Flips the sprite back to the front image and triggers haptic feedback if not already showing the front.
    /// - Parameter hapticFeedback: The haptic feedback generator.
    func flipSpriteBack(hapticFeedback: UIImpactFeedbackGenerator) {
        guard isFlipped else { return }
        isFlipped = false
        hapticFeedback.impactOccurred()
    }
}
