import SwiftUI

struct ShimmerModifier: ViewModifier {
    @State private var offset: CGFloat = -400

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.25), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: offset)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        offset = 400
                    }
                }
            )
            .clipped()
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}
