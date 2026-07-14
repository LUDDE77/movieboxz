import SwiftUI

#if os(tvOS)

// MARK: - Focus Variant

/// Three semantic variants for the tvOS focus border system.
enum FocusVariant {
    /// For content cards (movie cards, episode cards, series cards).
    /// Lifts up with shadow to emphasize browsing.
    case card(cornerRadius: CGFloat = 12)

    /// For primary action buttons (Watch, Play, Get Started).
    /// Subtle lift with a soft white glow instead of a heavy shadow.
    case action(cornerRadius: CGFloat = 10)

    /// For small utility controls (close, favorite, season pills).
    /// No scale change — just a clean border to indicate focusability.
    case utility(cornerRadius: CGFloat = 20)

    var resolvedCornerRadius: CGFloat {
        switch self {
        case .card(let r): return r
        case .action(let r): return r
        case .utility(let r): return r
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .card, .action: return 3
        case .utility: return 2
        }
    }

    var scale: CGFloat {
        switch self {
        case .card: return 1.05
        case .action: return 1.03
        case .utility: return 1.0
        }
    }

    var shadowColor: Color {
        switch self {
        case .card: return .black.opacity(0.45)
        case .action: return .mbzGold.opacity(0.35)
        case .utility: return .clear
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .card: return 14
        case .action: return 10
        case .utility: return 0
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .card: return 7
        case .action: return 4
        case .utility: return 0
        }
    }

    var animation: Animation {
        switch self {
        case .card, .action:
            return .spring(response: 0.25, dampingFraction: 0.75)
        case .utility:
            return .easeOut(duration: 0.15)
        }
    }
}

// MARK: - FocusBorderButtonStyle

/// Unified focus style for tvOS. Replaces Apple's grey `.card` box with a
/// crisp marquee-gold border that reflects the semantic purpose of the button.
struct FocusBorderButtonStyle: ButtonStyle {
    var variant: FocusVariant = .card()

    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: variant.resolvedCornerRadius)
                    .strokeBorder(Color.mbzGold, lineWidth: variant.borderWidth)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? variant.scale : 1.0)
            .shadow(
                color: isFocused ? variant.shadowColor : .clear,
                radius: variant.shadowRadius,
                y: variant.shadowY
            )
            .animation(variant.animation, value: isFocused)
    }
}

// MARK: - Convenience initialisers (backwards compatible)

extension FocusBorderButtonStyle {
    /// Legacy initialiser: `FocusBorderButtonStyle(cornerRadius: 10)` maps to `.card`.
    init(cornerRadius: CGFloat) {
        self.variant = .card(cornerRadius: cornerRadius)
    }
}

#endif
