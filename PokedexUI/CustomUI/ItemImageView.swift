import SwiftUI

struct ItemImageView: View {
    let viewModel: ItemImageViewModel

    var body: some View {
        Group {
            if let image = viewModel.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color(.darkGray)
            }
        }
        .task { await viewModel.loadImage() }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 38.0)
    }
}
