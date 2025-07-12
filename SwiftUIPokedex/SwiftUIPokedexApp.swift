import SwiftUI

@main
struct SwiftUIPokedexApp: App {
    var body: some Scene {
        WindowGroup {
            PokedexView(viewModel: PokedexViewModel())
        }
    }
}
