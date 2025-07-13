import Foundation

protocol ItemdetailViewModelProtocol {
    var items: [ItemDetail] { get }
    var title: String { get }
}

// MARK: -
final class ItemDetailViewModel {
    let item: ItemData

    init(item: ItemData) {
        self.item = item
    }
}

// MARK: - ItemdetailViewModelProtocol
extension ItemDetailViewModel: ItemdetailViewModelProtocol {
    var title: String {
        item.title?.pretty ?? "Unknown"
    }

    var items: [ItemDetail] {
        item.items
    }
}
