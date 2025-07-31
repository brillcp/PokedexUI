import Foundation

/// Protocol describing a view model that provides item details and a title for display.
protocol ItemDetailViewModelProtocol {
    /// The collection of item details to be displayed.
    var items: [ItemDetail] { get }
    /// The title representing this group of items.
    var title: String { get }
}

// MARK: -
/// View model that provides details and metadata for a single item, conforming to `ItemdetailViewModelProtocol`.
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

    /// The details for each item associated with this data.
    var items: [ItemDetail] {
        item.items
    }
}
