import SwiftUI

extension EnvironmentValues {
    /// The composition root that every view + viewmodel reads its services from.
    /// Override with `.environment(\.container, mockContainer)` in tests/previews.
    @Entry var container: AppContainer = .live
}
