import SwiftUI

/// YouTube TOS-compliant attribution badge
struct YouTubeAttribution: View {
    enum Style {
        case compact   // Small badge for cards
        case full      // Full attribution for detail views
    }

    var style: Style = .compact

    var body: some View {
        switch style {
        case .compact:
            compactBadge
        case .full:
            fullAttribution
        }
    }

    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 10))
            Text("YouTube")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.7))
        .cornerRadius(4)
    }

    private var fullAttribution: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("Powered by YouTube")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Video content hosted on YouTube")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}
