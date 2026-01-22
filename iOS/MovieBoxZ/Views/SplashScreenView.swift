import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var splashOpacity = 1.0
    @State private var contentOpacity = 0.0
    @State private var scale = 0.8

    var body: some View {
        ZStack {
            // Content View (behind splash)
            ContentView()
                .opacity(contentOpacity)

            // Splash Screen (on top, fades out)
            if !isActive {
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
                .opacity(splashOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.5)) {
                        scale = 1.0
                    }

                    // Show splash for 2 seconds, then fade out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            splashOpacity = 0.0
                            contentOpacity = 1.0
                        }

                        // Remove splash from view hierarchy after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isActive = true
                        }
                    }
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
