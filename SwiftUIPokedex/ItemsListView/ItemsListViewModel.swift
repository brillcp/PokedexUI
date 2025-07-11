import Foundation

protocol ItemsListViewModelProtocol: ObservableObject {
    var query: String { get set }

    func search() async
    func clearSearch(_ oldValue: String, _ newValue: String)
}

// MARK: -
final class ItemsListViewModel {
    @Published var query: String = ""

}

// MARK: - ItemsListViewModelProtocol
extension ItemsListViewModel: ItemsListViewModelProtocol {
    func search() async {

    }

    func clearSearch(_ oldValue: String, _ newValue: String) {

    }
}
