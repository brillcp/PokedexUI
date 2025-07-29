import SwiftUI

struct ItemSpriteView: View {
    let viewModel: ItemSpriteViewModel

    var body: some View {
        Group {
            if let sprite = viewModel.sprite {
                sprite
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color(.darkGray)
            }
        }
        .task { await viewModel.loadSprite() }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 38.0)
    }
}
