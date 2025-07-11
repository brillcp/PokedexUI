import Foundation

protocol ItemsListViewModelProtocol: ObservableObject {
    var items: [ItemData] { get }
    var query: String { get set }

    func loadItems() async
    func search() async
    func clearSearch(_ oldValue: String, _ newValue: String)
}

// MARK: -
final class ItemsListViewModel {
    private let itemService: ItemServiceV2

    @Published var items: [ItemData] = []
    @Published var query: String = ""

    init(itemService: ItemServiceV2 = ItemServiceV2()) {
        self.itemService = itemService
    }
}

// MARK: - ItemsListViewModelProtocol
extension ItemsListViewModel: ItemsListViewModelProtocol {
    @MainActor
    func loadItems() async {
        do {
            items = try await itemService.requestItems()
            print()
        } catch {
            print()
        }
    }

    func search() async {

    }

    func clearSearch(_ oldValue: String, _ newValue: String) {

    }
}
