//
//  ItemRowView.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2025-07-12.
//

import SwiftUI

struct ItemRowView: View {
    private let imageLoader = ImageLoader()

    @State private var image: Image?

    let item: ItemDetails

    var body: some View {
        HStack(alignment: .top) {
            sprite
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 16) {
                Text(item.name.pretty)
                Text(item.effect.first?.description ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical)
        .task { image = await loadImage() }
    }
}

// MARK: - Private properties
private extension ItemRowView {
    var sprite: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    func loadImage() async -> Image {
        let uiImage = await imageLoader.loadImage(from: item.sprites.default)
        return Image(uiImage: uiImage ?? UIImage())
    }
}

#Preview {
    ItemRowView(item: .common)
}
