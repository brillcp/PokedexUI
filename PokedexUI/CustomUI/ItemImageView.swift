import SwiftUI

struct ItemImageView: View {
    private var viewModel: ItemViewModel
    private let imageURL: String?
    private let size: CGFloat

    init(imageURL: String?, size: CGFloat = 38.0, imageLoader: ImageLoader = ImageLoader()) {
        self.imageURL = imageURL
        self.size = size
        self.viewModel = ItemViewModel(imageLoader: imageLoader)
    }

    var body: some View {
        Group {
            if let image = viewModel.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color(.darkGray)
                    .clipShape(RoundedRectangle(cornerRadius: 8.0))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size)
        .task {
            await viewModel.loadImage(from: imageURL)
        }
    }
}
