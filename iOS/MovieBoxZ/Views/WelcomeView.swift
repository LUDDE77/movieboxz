import SwiftUI

// MARK: - Welcome View
// First-launch screen explaining YouTube requirement

struct WelcomeView: View {
    @Binding var hasSeenWelcome: Bool
    // Recording acceptance of the current Terms happens here, alongside
    // hasSeenWelcome, whenever the user taps Get Started (or Continue Anyway).
    @AppStorage("acceptedTermsVersion") private var acceptedTermsVersion = 0
    @State private var showYouTubeAlert = false
    @State private var showTermsOfService = false
    @State private var showPrivacyPolicy = false
    @FocusState private var buttonFocused: Bool  // Focus management for tvOS

    /// Marks the Welcome flow complete and records acceptance of the current
    /// Terms/Privacy version. Called from every path that dismisses Welcome.
    private func acceptAndContinue() {
        acceptedTermsVersion = LegalContent.termsVersion
        hasSeenWelcome = true
    }

    #if os(tvOS)
    private let appIconSize: CGFloat = 200
    private let appNameFontSize: CGFloat = 80
    private let taglineFontSize: CGFloat = 36
    #else
    private let appIconSize: CGFloat = 120
    private let appNameFontSize: CGFloat = 48
    private let taglineFontSize: CGFloat = 20
    #endif

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.mbzInk,
                    Color.mbzSlate,
                    Color.mbzInk
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
                                    gradient: Gradient(colors: [.mbzGold, .mbzGoldHi]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: appIconSize, height: appIconSize)

                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: appIconSize * 0.5))
                            .foregroundColor(.mbzInk)
                    }
                    .shadow(radius: 20)

                    // App name and tagline
                    VStack(spacing: 8) {
                        Text("MovieBoxZ")
                            .font(.system(size: appNameFontSize, weight: .bold, design: .rounded))
                            .foregroundColor(.mbzScreen)

                        Text("Discover Movies from YouTube")
                            .font(.system(size: taglineFontSize, weight: .medium))
                            .foregroundColor(.mbzMuted)
                            .multilineTextAlignment(.center)
                    }

                    // Feature list
                    VStack(alignment: .leading, spacing: 24) {
                        FeatureRow(
                            icon: "magnifyingglass.circle.fill",
                            iconColor: .mbzGold,
                            title: "Discover Movies",
                            description: "Browse thousands of movies from curated YouTube channels"
                        )

                        FeatureRow(
                            icon: "play.rectangle.fill",
                            iconColor: .mbzRed,
                            title: "Watch on YouTube",
                            description: "All videos play in the official YouTube app for the best experience"
                        )

                        FeatureRow(
                            icon: "bookmark.circle.fill",
                            iconColor: .mbzGold,
                            title: "Build Your Library",
                            description: "Save your favorites and track what you've watched"
                        )

                        FeatureRow(
                            icon: "tv.circle.fill",
                            iconColor: .mbzGold,
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
                                .foregroundColor(.mbzGold)

                            Text("YouTube App Required")
                                .font(.headline)
                                .foregroundColor(.mbzScreen)
                        }

                        Text("MovieBoxZ is a discovery and catalog app. All videos are hosted on YouTube and play in the official YouTube app. This ensures the best quality and supports content creators.")
                            .font(.subheadline)
                            .foregroundColor(.mbzMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.mbzGold.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.mbzGold.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 20)

                    // Get started button
                    VStack(spacing: 12) {
                        Button {
                            #if os(tvOS)
                            // On tvOS, skip YouTube detection and proceed directly
                            // User can browse regardless of YouTube app installation
                            acceptAndContinue()
                            #else
                            // On iOS, check if YouTube is installed
                            if YouTubePlayerService.shared.isYouTubeAppInstalled() {
                                acceptAndContinue()
                            } else {
                                showYouTubeAlert = true
                            }
                            #endif
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
                                    gradient: Gradient(colors: [.mbzGold, .mbzGoldHi]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.mbzInk)
                            .cornerRadius(12)
                        }
                        #if os(tvOS)
                        .buttonStyle(FocusBorderButtonStyle(variant: .action(cornerRadius: 12)))
                        #endif
                        .focused($buttonFocused)  // Attach focus state for tvOS
                        .shadow(radius: 10)

                        Text("By tapping Get Started you agree to our Terms of Service and Privacy Policy.")
                            .font(.caption)
                            .foregroundColor(.mbzMuted)
                            .multilineTextAlignment(.center)

                        // Read-before-accept: open the same in-app pop-ups used
                        // in Settings so the user can review before tapping.
                        HStack(spacing: 24) {
                            Button {
                                showTermsOfService = true
                            } label: {
                                Text("Terms of Service")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.mbzGold)
                            }
                            #if os(tvOS)
                            .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 8)))
                            #endif

                            Button {
                                showPrivacyPolicy = true
                            } label: {
                                Text("Privacy Policy")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.mbzGold)
                            }
                            #if os(tvOS)
                            .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 8)))
                            #endif
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .onAppear {
            // tvOS: Set initial focus on button after view renders
            #if os(tvOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                buttonFocused = true
            }
            #endif
        }
        .alert("YouTube App Required", isPresented: $showYouTubeAlert) {
            #if os(iOS)
            Button("Install YouTube") {
                YouTubePlayerService.shared.promptInstallYouTubeApp()
            }
            #endif
            Button("Continue Anyway") {
                acceptAndContinue()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("MovieBoxZ requires the YouTube app to play videos. You can browse movies, but you'll need to install YouTube to watch them.\n\nDownload the free YouTube app from the App Store to get started.")
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $showTermsOfService) {
            LegalDocumentView(title: "Terms of Service", text: LegalContent.termsOfService)
        }
        .fullScreenCover(isPresented: $showPrivacyPolicy) {
            LegalDocumentView(title: "Privacy Policy", text: LegalContent.privacyPolicy)
        }
        #else
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentView(title: "Terms of Service", text: LegalContent.termsOfService)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentView(title: "Privacy Policy", text: LegalContent.privacyPolicy)
        }
        #endif
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
                    #if os(tvOS)
                    .frame(width: 80, height: 80)
                    #else
                    .frame(width: 48, height: 48)
                    #endif

                Image(systemName: icon)
                    #if os(tvOS)
                    .font(.system(size: 40))
                    #else
                    .font(.title2)
                    #endif
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    #if os(tvOS)
                    .font(.system(size: 32, weight: .semibold))
                    #else
                    .font(.headline)
                    #endif
                    .foregroundColor(.mbzScreen)

                Text(description)
                    #if os(tvOS)
                    .font(.system(size: 26))
                    #else
                    .font(.subheadline)
                    #endif
                    .foregroundColor(.mbzMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

#Preview {
    WelcomeView(hasSeenWelcome: .constant(false))
}
