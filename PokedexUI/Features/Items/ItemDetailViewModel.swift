import Foundation

/// Protocol for a view model that provides item details and a title for display.
@MainActor
protocol ItemDetailViewModelProtocol {
    /// The collection of item details to be displayed.
    var items: [ItemDetail] { get }
    /// The title representing this group of items.
    var title: String { get }
}

/// View model that provides details and metadata for a single item.
@MainActor
@Observable
final class ItemDetailViewModel {
    let item: ItemData

    init(item: ItemData) {
        self.item = item
    }
}

// MARK: - ItemDetailViewModelProtocol

extension ItemDetailViewModel: ItemDetailViewModelProtocol {
    var title: String {
        item.title.pretty
    }

    var items: [ItemDetail] {
        item.items.sorted(by: { $0.name < $1.name })
    }
}
