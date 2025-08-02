import SwiftUI

/// ViewModel responsible for loading and storing a sprite image for a UI item.
/// Utilizes an ImageLoader to fetch images asynchronously and exposes loading state.
final class ItemSpriteViewModel {
    /// The url string to load the sprite from.
    let spriteURL: String

    /// Initializes the ItemSpriteViewModel with the provided sprite URL.
    ///
    /// - Parameter spriteURL: The URL string pointing to the sprite image that should be loaded and managed by this view model.
    init(spriteURL: String) {
        self.spriteURL = spriteURL
    }
}
