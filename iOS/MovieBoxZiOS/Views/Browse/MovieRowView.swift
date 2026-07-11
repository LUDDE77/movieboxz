import SwiftUI

struct MovieRowView: View {
    let title: String
    let movies: [Movie]
    let screenWidth: CGFloat
    let onTap: (Movie) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        Text("See All")
                            .font(.system(size: 13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(width: screenWidth)

            // Horizontal carousel
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(movies.prefix(12)) { movie in
                        MovieCard(movie: movie, onTap: { onTap(movie) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .frame(width: screenWidth)
        }
    }
}
