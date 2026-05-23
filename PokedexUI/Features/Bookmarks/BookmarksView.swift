import SwiftUI
import SwiftData

/// Bookmarks tab showing Pokemon rows filtered by `isBookmarked`.
struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Pokemon> { $0.isBookmarked },
        sort: \.id
    ) private var bookmarks: [Pokemon]

    var body: some View {
        NavigationStack {
            PokedexGridView(pokemon: bookmarks)
                .overlay {
                    if bookmarks.isEmpty {
                        Text("No favourites")
                            .foregroundStyle(.secondary)
                            .font(.pixel14)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    BookmarksView()
}
