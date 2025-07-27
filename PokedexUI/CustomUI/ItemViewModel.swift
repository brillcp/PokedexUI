import SwiftUI

@MainActor
@Observable
final class ItemViewModel {
    private let imageLoader: ImageLoader

    var image: Image?
    var isLoading = false

    init(imageLoader: ImageLoader = .init()) {
        self.imageLoader = imageLoader
    }
}

// MARK: - Publid functions
extension ItemViewModel {
    func loadImage(from url: String?) async {
        guard let url else { return }

        isLoading = true
        let uiImage = await imageLoader.loadImage(from: url)
        image = Image(uiImage: uiImage ?? UIImage())
        isLoading = false
    }
}
