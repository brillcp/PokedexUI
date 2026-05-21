import SwiftUI

/// Full-width primary action button with pixel font and red glass tint.
struct PrimaryCapsuleButton: View {
    let icon: String
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    PixelSpinner(color: .white)
                } else {
                    Image(systemName: icon)
                }
                Text(isLoading ? "Thinking": title)
            }
            .font(.pixel17)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .foregroundStyle(.white)
        }
        .glassEffect(.clear.tint(.pokedexRed.opacity(0.8)).interactive())
        .opacity(isEnabled && !isLoading ? 1 : Opacity.disabled)
        .disabled(!isEnabled || isLoading)
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
        .opacity(isEnabled ? 1 : Opacity.disabled)
        .disabled(!isEnabled)
    }
}
