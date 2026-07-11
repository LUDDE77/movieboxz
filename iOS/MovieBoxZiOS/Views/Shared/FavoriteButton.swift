import SwiftUI

struct FavoriteButton: View {
    let movieId: String
    let movieTitle: String
    let posterURL: String?
    @State private var isFav: Bool = false

    var body: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isFav ? .red : .white)
                .padding(10)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isFav)
        .task {
            isFav = LibraryManager.shared.isFavorite(movieId)
        }
    }

    private func toggle() {
        HapticFeedback.light()
        if isFav {
            LibraryManager.shared.removeFromFavorites(movieId)
        } else {
            LibraryManager.shared.addToFavorites(movieId)
        }
        isFav.toggle()
    }
}
