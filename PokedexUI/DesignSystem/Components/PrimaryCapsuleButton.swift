import SwiftUI

/// Full-width primary action button used throughout the battle flow: the
/// opponent picker's Random / Smart pick row and the loadout screen's
/// Battle / Pick-N-more CTA. Pixel font, red glass tint, capsule shape; the
/// caller controls outer padding and the enabled state.
struct PrimaryCapsuleButton: View {
    let icon: String
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.pixel17)
                .frame(maxWidth: .infinity)
                .padding(.vertical)
                .foregroundStyle(.white)
        }
        .glassEffect(.clear.tint(.pokedexRed.opacity(0.8)).interactive(), in: Capsule())
        .opacity(isEnabled ? 1 : 0.6)
        .disabled(!isEnabled)
    }
}

struct SecondaryCapsuleButton: View {
    let icon: String
    let title: String
    let color: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.pixel14)
                .padding(.vertical, 11)
                .padding(.horizontal)
                .foregroundStyle(color)
        }
        .glassEffect(.clear.interactive(), in: Capsule())
        .opacity(isEnabled ? 1 : 0.6)
        .disabled(!isEnabled)
    }
}
