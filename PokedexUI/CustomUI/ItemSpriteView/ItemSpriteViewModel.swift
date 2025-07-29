import SwiftUI

/// ViewModel responsible for loading and storing a sprite image for a UI item.
/// Utilizes an ImageLoader to fetch images asynchronously and exposes loading state.
@MainActor
@Observable
final class ItemSpriteViewModel {
    /// Loader responsible for fetching images from a remote or local source.
    private let spriteLoader: SpriteLoader
    /// The url string to load the sprite from.
    private let spriteURL: String

    /// The loaded SwiftUI Image, if available.
    var sprite: Image?
    /// Indicates whether an image is currently being loaded.
    var isLoading = false

    /// Initializes the view model with an optional custom ImageLoader.
    /// - Parameter spriteLoader: The image loader to use (default creates a new instance).
    init(spriteURL: String, spriteLoader: SpriteLoader = .init()) {
        self.spriteURL = spriteURL
        self.spriteLoader = spriteLoader
    }
}

// MARK: - Publid functions
extension ItemSpriteViewModel {
    /// Loads an image from a given URL string asynchronously, updating the image and loading state.
    func loadSprite() async {
        isLoading = true
        let uiImage = await spriteLoader.loadSprite(from: spriteURL)
        sprite = Image(uiImage: uiImage ?? UIImage())
        isLoading = false
    }
}
