import SwiftUI

struct SplashScreenView: View {
    @State private var showContent = false
    @State private var scale: CGFloat = 0.8

    var body: some View {
        ZStack {
            ContentView()
                .opacity(showContent ? 1 : 0)
                .ignoresSafeArea()

            if !showContent {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 24) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 100))
                            .foregroundStyle(LinearGradient(colors: [.red, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .scaleEffect(scale)
                        Text("MovieBoxZ")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Version \(appVersion)")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: showContent)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeIn(duration: 0.5)) { scale = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) { showContent = true }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
