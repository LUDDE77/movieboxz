import SwiftUI

// MARK: - Welcome View
// First-launch screen explaining YouTube requirement

struct WelcomeView: View {
    @Binding var hasSeenWelcome: Bool
    @State private var showYouTubeAlert = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(red: 0.1, green: 0.0, blue: 0.1),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 40)

                    // App icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.red, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                    }
                    .shadow(radius: 20)

                    // App name and tagline
                    VStack(spacing: 8) {
                        Text("MovieBoxZ")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Discover Movies from YouTube")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    // Feature list
                    VStack(alignment: .leading, spacing: 24) {
                        FeatureRow(
                            icon: "magnifyingglass.circle.fill",
                            iconColor: .blue,
                            title: "Discover Movies",
                            description: "Browse thousands of movies from curated YouTube channels"
                        )

                        FeatureRow(
                            icon: "play.rectangle.fill",
                            iconColor: .red,
                            title: "Watch on YouTube",
                            description: "All videos play in the official YouTube app for the best experience"
                        )

                        FeatureRow(
                            icon: "bookmark.circle.fill",
                            iconColor: .green,
                            title: "Build Your Library",
                            description: "Save your favorites and track what you've watched"
                        )

                        FeatureRow(
                            icon: "tv.circle.fill",
                            iconColor: .purple,
                            title: "Multi-Platform",
                            description: "Available on iPhone, iPad, and Apple TV"
                        )
                    }
                    .padding(.horizontal, 32)

                    // YouTube requirement notice
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)

                            Text("YouTube App Required")
                                .font(.headline)
                                .foregroundColor(.white)
                        }

                        Text("MovieBoxZ is a discovery and catalog app. All videos are hosted on YouTube and play in the official YouTube app. This ensures the best quality and supports content creators.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.yellow.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 20)

                    // Get started button
                    VStack(spacing: 12) {
                        Button {
                            if YouTubePlayerService.shared.isYouTubeAppInstalled() {
                                hasSeenWelcome = true
                            } else {
                                showYouTubeAlert = true
                            }
                        } label: {
                            HStack {
                                Text("Get Started")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.right")
                            }
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.red, .purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .shadow(radius: 10)

                        Text("By continuing, you agree to YouTube's Terms of Service")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .alert("YouTube App Required", isPresented: $showYouTubeAlert) {
            #if os(iOS)
            Button("Install YouTube") {
                YouTubePlayerService.shared.promptInstallYouTubeApp()
            }
            #endif
            Button("Continue Anyway") {
                hasSeenWelcome = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("MovieBoxZ requires the YouTube app to play videos. You can browse movies, but you'll need to install YouTube to watch them.\n\nDownload the free YouTube app from the App Store to get started.")
        }
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

#Preview {
    WelcomeView(hasSeenWelcome: .constant(false))
}
