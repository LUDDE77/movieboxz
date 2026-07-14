import SwiftUI

// MARK: - Favorite Button
// Heart icon button for adding/removing movies from favorites
// Integrates with LibraryManager for persistence

struct FavoriteButton: View {
    let movieId: String
    @ObservedObject private var libraryManager = LibraryManager.shared

    // Platform-specific sizes
    #if os(tvOS)
    private let iconSize: CGFloat = 42
    private let padding: CGFloat = 20
    #else
    private let iconSize: CGFloat = 24
    private let padding: CGFloat = 12
    #endif

    private var isFavorite: Bool {
        libraryManager.isFavorite(movieId)
    }

    var body: some View {
        Button {
            #if os(iOS)
            HapticFeedback.light()
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                libraryManager.toggleFavorite(movieId)
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: iconSize))
                .foregroundColor(isFavorite ? .mbzGold : .mbzScreen)
                .padding(padding)
                .background(
                    Circle()
                        .fill(Color.mbzInk.opacity(0.6))
                        .shadow(color: .black.opacity(0.3), radius: 8)
                )
        }
        #if os(tvOS)
        .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 100)))
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityHint(isFavorite ? "Removes this movie from your library" : "Saves this movie to your library")
    }
}

// MARK: - Preview

#Preview("Not Favorite") {
    ZStack {
        Color.black.ignoresSafeArea()

        FavoriteButton(movieId: "test123")
    }
    .preferredColorScheme(.dark)
}

#Preview("Is Favorite") {
    struct PreviewWrapper: View {
        init() {
            // Add to favorites for preview
            LibraryManager.shared.addToFavorites("test456")
        }

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                FavoriteButton(movieId: "test456")
            }
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
