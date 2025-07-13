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
    private let itemService: ItemService
    private var allItems: [ItemData] = []

    @Published var items: [ItemData] = []
    @Published var query: String = ""

    init(itemService: ItemService = ItemService()) {
        self.itemService = itemService
    }
}

// MARK: - ItemsListViewModelProtocol
extension ItemsListViewModel: ItemsListViewModelProtocol {
    @MainActor
    func loadItems() async {
        guard items.isEmpty else { return }

        do {
            let data = try await itemService.requestItems()
            allItems = data
            items = data
        } catch {
            print(error.localizedDescription)
        }
    }

    @MainActor
    func search() async {
        guard !query.isEmpty else {
            items = allItems
            return
        }

        if allItems.isEmpty {
            await loadItems()
        }

        items = itemService.searchItems(matching: query)
    }

    func clearSearch(_ oldValue: String, _ newValue: String) {
        guard newValue.isEmpty else { return }
        items = allItems
    }
}
