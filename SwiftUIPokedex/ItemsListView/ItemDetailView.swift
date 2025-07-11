//
//  ItemDetailView.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2025-07-11.
//

import SwiftUI

struct ItemDetailView: View {
    private let imageLoader = ImageLoader()

    @State private var image: Image?

    let item: ItemData

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading) {
                    ForEach(item.items, id: \.id) { item in
                        HStack(alignment: .top) {
                            sprite(item: item)

                            VStack(alignment: .leading, spacing: 16.0) {
                                Text("\(item.name)")
                                Text("\(item.effect.first?.description ?? "")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical)

                        Divider()
                            .background(.secondary)
                    }
                }
                .font(.pixel14)
                .foregroundStyle(.white)
                .padding()
            }
            .applyPokedexStyling(title: item.title ?? "Unknown")
        }
    }
}

// MARK: - Private functions
private extension ItemDetailView {
    func sprite(item: ItemDetails) -> some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .tint(.white)
                    .task {
                        image = await image(item: item)
                    }
            }
        }
        .frame(width: 32.0)
    }

    func image(item: ItemDetails) async -> Image {
        let uiImage = await imageLoader.loadImage(from: item.sprites.default)
        return Image(uiImage: uiImage ?? UIImage())
    }
}

#Preview {
    let details: ItemDetails = .init(
        id: 0,
        name: "Item",
        sprites: .init(
            default: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/honey.png"
        ),
        category: .init(name: "category", url: ""),
        effect: [
            .init(description: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat")
        ]
    )
    ItemDetailView(item: .init(title: "Item", items: [details]))
}
