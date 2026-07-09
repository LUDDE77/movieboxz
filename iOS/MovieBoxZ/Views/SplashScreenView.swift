import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject private var movieService: MovieService
    @State private var showContent = false
    @State private var scale = 0.8

    // Race the real data-readiness check against a hard cap so a slow/failed
    // network never blocks the splash screen forever, while a minimum keeps
    // it from flashing on-screen for a fast connection.
    private let minDisplayDuration: UInt64 = 800_000_000   // 0.8s
    private let maxWaitDuration: UInt64 = 1_800_000_000    // 1.8s

    var body: some View {
        ZStack {
            // Content View (behind splash)
            ContentView()
                .opacity(showContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: showContent)
                #if os(iOS)
                .ignoresSafeArea()
                #endif

            // Splash Screen (on top, fades out)
            if !showContent {
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
                        Text("Version \(AppVersion.fullVersion)")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 20)
                    }
                }
                .opacity(!showContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: showContent)
            }
        }
        #if os(iOS)
        .ignoresSafeArea()
        #endif
        .onAppear {
            // Animate logo scale
            withAnimation(.easeIn(duration: 0.5)) {
                scale = 1.0
            }

            Task {
                await waitForReadinessThenReveal()
            }
        }
    }

    /// Races real data-readiness (preloading Browse data on the shared
    /// MovieService) against a hard timeout, then enforces a minimum
    /// display duration so the splash never reloads instantly if the
    /// network is fast, and never hangs forever if it's slow/offline.
    private func waitForReadinessThenReveal() async {
        let start = DispatchTime.now().uptimeNanoseconds

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await movieService.loadBrowseData()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: maxWaitDuration)
            }
            // Proceed as soon as either finishes (data ready, or we hit the cap).
            _ = await group.next()
            group.cancelAll()
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed < minDisplayDuration {
            try? await Task.sleep(nanoseconds: minDisplayDuration - elapsed)
        }

        withAnimation(.easeOut(duration: 0.5)) {
            showContent = true
        }
    }
}

#Preview {
    SplashScreenView()
        .environmentObject(MovieService())
        .preferredColorScheme(.dark)
}
