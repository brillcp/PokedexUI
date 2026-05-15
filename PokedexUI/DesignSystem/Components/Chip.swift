import SwiftUI

/// Small inline pill used throughout the app — type chips, generation badges,
/// effectiveness markers, status tags, etc. All chips share the same squared
/// 4-point corner radius so the gameboy-style aesthetic is consistent
/// (capsule corners look too modern next to the pixel font).
///
/// Pass a `Style` to switch between the common tint variants instead of
/// passing raw colors at every call site. Custom one-offs can use `.custom`.
struct Chip: View {
    let text: String
    let style: Style
    let size: Size

    init(_ text: String, style: Style = .neutral, size: Size = .small) {
        self.text = text
        self.style = style
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(size.font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(style.foreground)
            .background(style.background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Style

extension Chip {
    /// Visual tint of the chip. Map any new use case to one of these instead
    /// of inventing a color inline at the call site.
    enum Style {
        /// Subtle white-on-dark fill. Default for type tags and metadata.
        case neutral
        /// Translucent accent — used for "GEN I" style version badges.
        case accent
        /// Red call-out — legendary, mythical, VS badges.
        case primary
        /// Green — super-effective markers, "x2" / win banners.
        case success
        /// Red — resisted-effectiveness, lose banners.
        case danger
        /// Caller-supplied colors for one-off variants.
        case custom(background: Color, foreground: Color = .white)

        var background: Color {
            switch self {
            case .neutral: return .white.opacity(0.15)
            case .accent:  return .white.opacity(0.1)
            case .primary: return Color.pokedexRed?.opacity(0.7) ?? .red
            case .success: return .green.opacity(0.4)
            case .danger:  return .red.opacity(0.4)
            case .custom(let bg, _): return bg
            }
        }

        var foreground: Color {
            switch self {
            case .neutral, .accent, .success, .danger: return .white
            case .primary: return .white
            case .custom(_, let fg): return fg
            }
        }
    }

    /// Font + padding scale. `small` is the default chip — `medium` is for
    /// hero badges like the "VS" between two fighter cards.
    enum Size {
        case small
        case medium

        var font: Font {
            switch self {
            case .small:  return .pixel9
            case .medium: return .pixel12
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small:  return 6
            case .medium: return 8
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small:  return 2
            case .medium: return 4
            }
        }
    }
}
