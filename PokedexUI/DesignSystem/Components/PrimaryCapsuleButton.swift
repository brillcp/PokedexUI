import SwiftUI

/// Full-width primary action button with pixel font and red glass tint.
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
        .glassEffect(.clear.tint(.pokedexRed.opacity(0.8)).interactive())
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
        .glassEffect(.clear.interactive())
        .opacity(isEnabled ? 1 : 0.6)
        .disabled(!isEnabled)
    }
}
