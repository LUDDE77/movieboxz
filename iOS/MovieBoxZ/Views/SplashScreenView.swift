import SwiftUI

struct SplashScreenView: View {
    @State private var showContent = false
    @State private var isReady = false  // Ensures view is ready before animating
    @State private var scale = 0.8

    var body: some View {
        ZStack {
            // Content View (behind splash)
            ContentView()
                .opacity(showContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: showContent)

            // Splash Screen (on top, fades out)
            if !showContent || !isReady {
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack(spacing: 30) {
                        // Logo
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 120))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.red, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(scale)

                        // App Name
                        Text("MovieBoxZ")
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        // Version Number - CRITICAL FOR VERIFICATION
                        VStack(spacing: 8) {
                            Text("Version \(AppVersion.fullVersion)")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

                            Text("Build Date: \(buildDate)")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.top, 20)
                    }
                }
                .opacity(isReady && !showContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: showContent)
            }
        }
        .onAppear {
            // Step 1: Mark view as ready (synchronous)
            isReady = true

            // Step 2: Animate logo scale
            withAnimation(.easeIn(duration: 0.5)) {
                scale = 1.0
            }

            // Step 3: Start transition after 2 second delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showContent = true
                }
            }
        }
    }

    private var buildDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy HH:mm"
        return formatter.string(from: Date())
    }
}

#Preview {
    SplashScreenView()
        .preferredColorScheme(.dark)
}
