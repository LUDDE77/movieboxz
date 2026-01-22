import SwiftUI

// MARK: - Loading Skeleton Views
// Shown while content is loading to provide visual feedback

struct LoadingSkeletonView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero banner skeleton
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    #if os(tvOS)
                    .frame(height: 600)
                    #else
                    .frame(height: 500)
                    #endif
                    .shimmer()

                #if os(tvOS)
                VStack(spacing: 60) {
                    ForEach(0..<3) { _ in
                        CarouselSkeletonView()
                    }
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)
                #else
                VStack(spacing: 30) {
                    ForEach(0..<3) { _ in
                        CarouselSkeletonView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                #endif
            }
        }
        .background(Color.black)
    }
}

struct CarouselSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Section header skeleton
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                #if os(tvOS)
                .frame(width: 300, height: 42)
                #else
                .frame(width: 200, height: 24)
                #endif
                .shimmer()

            // Movie cards skeleton
            ScrollView(.horizontal, showsIndicators: false) {
                #if os(tvOS)
                HStack(spacing: 40) {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            // Poster skeleton
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 350, height: 525)
                                .cornerRadius(12)
                                .shimmer()

                            // Title skeleton
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 300, height: 31)
                                .shimmer()

                            // Metadata skeleton
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 200, height: 25)
                                .shimmer()
                        }
                        .frame(width: 350)
                    }
                }
                #else
                HStack(spacing: 15) {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            // Poster skeleton
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 150, height: 225)
                                .cornerRadius(8)
                                .shimmer()

                            // Title skeleton
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 130, height: 18)
                                .shimmer()

                            // Metadata skeleton
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 100, height: 14)
                                .shimmer()
                        }
                        .frame(width: 150)
                    }
                }
                #endif
            }
        }
    }
}

#Preview {
    LoadingSkeletonView()
        .preferredColorScheme(.dark)
}
