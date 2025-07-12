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
            items = try await itemService.requestItems()
        } catch {
            print(error.localizedDescription)
        }
    }

    func search() async {

    }

    func clearSearch(_ oldValue: String, _ newValue: String) {

    }
}
