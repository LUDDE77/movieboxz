import SwiftUI

struct LoadingSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Hero skeleton
            Color.gray.opacity(0.2)
                .shimmer()
                .frame(maxWidth: .infinity)
                .frame(height: 300)

            // Carousel skeletons
            VStack(spacing: 32) {
                ForEach(0..<3, id: \.self) { _ in
                    carouselSkeleton
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 16)
            .background(Color.black)

            Spacer()
        }
        .background(Color.black)
    }

    private var carouselSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.gray.opacity(0.3).shimmer().frame(width: 140, height: 18).cornerRadius(4)
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        Color.gray.opacity(0.25).shimmer().frame(width: 110, height: 165).cornerRadius(7)
                        Color.gray.opacity(0.2).shimmer().frame(width: 90, height: 11).cornerRadius(3)
                        Color.gray.opacity(0.15).shimmer().frame(width: 60, height: 10).cornerRadius(3)
                    }
                }
            }
        }
    }
}
