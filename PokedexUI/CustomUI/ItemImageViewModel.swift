import SwiftUI

/// ViewModel responsible for loading and storing an image for a UI item.
/// Utilizes an ImageLoader to fetch images asynchronously and exposes loading state.
@MainActor
@Observable
final class ItemImageViewModel {
    /// Loader responsible for fetching images from a remote or local source.
    private let imageLoader: ImageLoader
    /// The url string to load the sprite from.
    private let imageURL: String

    /// The loaded SwiftUI Image, if available.
    var image: Image?
    /// Indicates whether an image is currently being loaded.
    var isLoading = false

    /// Initializes the view model with an optional custom ImageLoader.
    /// - Parameter imageLoader: The image loader to use (default creates a new instance).
    init(imageURL: String, imageLoader: ImageLoader = .init()) {
        self.imageURL = imageURL
        self.imageLoader = imageLoader
    }
}

// MARK: - Publid functions
extension ItemImageViewModel {
    /// Loads an image from a given URL string asynchronously, updating the image and loading state.
    func loadImage() async {
        isLoading = true
        let uiImage = await imageLoader.loadImage(from: imageURL)
        image = Image(uiImage: uiImage ?? UIImage())
        isLoading = false
    }
}
