import Foundation

/// Protocol describing a view model that provides item details and a title for display.
protocol ItemDetailViewModelProtocol {
    /// The collection of item details to be displayed.
    var items: [ItemDetail] { get }
    /// The title representing this group of items.
    var title: String { get }
}

// MARK: -
/// View model that provides details and metadata for a single item,
/// conforming to `ItemDetailViewModelProtocol`. The underlying `ItemData`
/// is immutable for the view's lifetime, but the type is still
/// `@MainActor @Observable` so it matches every other SwiftUI-bound view
/// model in the app.
@MainActor
@Observable
final class ItemDetailViewModel {
    /// The raw item data backing this view model.
    let item: ItemData

    /// Initializes the view model with a specific item.
    /// - Parameter item: The item data to expose.
    init(item: ItemData) {
        self.item = item
    }
}

// MARK: - ItemdetailViewModelProtocol
extension ItemDetailViewModel: ItemDetailViewModelProtocol {
    /// The display title for this item, using a pretty format or "Unknown" if unavailable.
    var title: String {
        item.title.pretty
    }

    /// The details for each item associated with this data, sorted alphabetically by name.
    var items: [ItemDetail] {
        item.items.sorted(by: { $0.name < $1.name })
    }
}
