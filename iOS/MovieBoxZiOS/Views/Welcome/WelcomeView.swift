import SwiftUI

struct WelcomeView: View {
    @Binding var hasSeenWelcome: Bool
    @State private var showAlert = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.1, green: 0, blue: 0.1), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 30)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.red, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 100, height: 100)
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    .shadow(radius: 20)

                    VStack(spacing: 6) {
                        Text("MovieBoxZ")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Discover Movies from YouTube")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Features
                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(icon: "magnifyingglass.circle.fill", color: .blue,
                                   title: "Discover Movies",
                                   desc: "Browse thousands of movies from curated YouTube channels")
                        FeatureRow(icon: "play.rectangle.fill", color: .red,
                                   title: "Watch on YouTube",
                                   desc: "All videos play in the official YouTube app")
                        FeatureRow(icon: "heart.circle.fill", color: .pink,
                                   title: "Build Your Library",
                                   desc: "Save favourites and track what you've watched")
                    }
                    .padding(.horizontal, 24)

                    // YouTube notice
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill").foregroundColor(.yellow).font(.title3)
                        Text("MovieBoxZ requires the YouTube app to play videos. You can browse movies without it.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(16)
                    .background(Color.yellow.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3)))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)

                    // Get Started
                    Button {
                        if YouTubeService.shared.isYouTubeInstalled {
                            hasSeenWelcome = true
                        } else {
                            showAlert = true
                        }
                    } label: {
                        HStack {
                            Text("Get Started").fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                        }
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [.red, .purple], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .shadow(radius: 10)

                    Text("By continuing, you agree to YouTube's Terms of Service")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))

                    Spacer().frame(height: 20)
                }
            }
        }
        .alert("YouTube App Required", isPresented: $showAlert) {
            Button("Install YouTube") { YouTubeService.shared.promptInstallYouTube() }
            Button("Continue Anyway") { hasSeenWelcome = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MovieBoxZ needs the YouTube app to play videos. Install it free from the App Store.")
        }
    }
}

private struct FeatureRow: View {
    let icon: String; let color: Color; let title: String; let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.2)).frame(width: 44, height: 44)
                Image(systemName: icon).font(.title3).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundColor(.white)
                Text(desc).font(.subheadline).foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
