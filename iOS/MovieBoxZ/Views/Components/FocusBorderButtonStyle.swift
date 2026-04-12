import SwiftUI

#if os(tvOS)
/// Replaces tvOS's built-in .card button style.
/// Instead of a puffy grey box, shows a crisp 3pt white border
/// that appears on focus with a subtle scale (1.05) and shadow.
struct FocusBorderButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(
                color: .black.opacity(isFocused ? 0.45 : 0.15),
                radius: isFocused ? 14 : 4,
                y: isFocused ? 7 : 2
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isFocused)
    }
}
#endif
