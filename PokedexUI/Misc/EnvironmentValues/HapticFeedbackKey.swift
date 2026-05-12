import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var hapticFeedback: UIImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
}
