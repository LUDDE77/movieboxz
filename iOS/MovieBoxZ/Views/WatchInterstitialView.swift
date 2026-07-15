import SwiftUI

/// Full-screen pre-roll shown between tapping "Watch on YouTube" and the
/// hand-off to the YouTube app. For now it shows the MovieBoxZ branded splash
/// on a timer; later this is the seam where a Google AdMob interstitial (iOS)
/// is presented instead — `onComplete` fires when the ad/splash finishes.
///
/// IMPORTANT (policy): this screen intentionally shows NO YouTube content —
/// no thumbnail, title, or player — only MovieBoxZ branding, so any future ad
/// does not sit on a screen displaying YouTube API content.
struct WatchInterstitialView: View {
    let onComplete: () -> Void
    let onCancel: () -> Void
    var duration: Double = 4.0

    @State private var progress: CGFloat = 0
    @State private var pulse = false

    #if os(tvOS)
    private let logoSize: CGFloat = 200
    private let ringSize: CGFloat = 300
    private let titleSize: CGFloat = 34
    private let subtitleSize: CGFloat = 22
    #else
    private let logoSize: CGFloat = 120
    private let ringSize: CGFloat = 176
    private let titleSize: CGFloat = 24
    private let subtitleSize: CGFloat = 15
    #endif

    var body: some View {
        ZStack {
            Color.mbzInk.ignoresSafeArea()

            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .stroke(Color.mbzSlate, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.mbzGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                        .scaleEffect(pulse ? 1.04 : 1.0)
                }
                .frame(width: ringSize, height: ringSize)

                VStack(spacing: 8) {
                    Text("Getting your movie ready")
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundColor(.mbzScreen)
                    Text("Continuing to YouTube…")
                        .font(.system(size: subtitleSize))
                        .foregroundColor(.mbzMuted)
                }
            }

            // Cancel / back out
            VStack {
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: subtitleSize + 2, weight: .bold))
                            .foregroundColor(.mbzMuted)
                            .padding(20)
                    }
                    #if os(tvOS)
                    .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 100)))
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .accessibilityLabel("Cancel")
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        // `.task` is cancelled automatically if the view is dismissed (e.g. the
        // user taps cancel), so onComplete never fires after a cancel.
        .task {
            withAnimation(.linear(duration: duration)) { progress = 1.0 }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onComplete()
        }
    }
}
