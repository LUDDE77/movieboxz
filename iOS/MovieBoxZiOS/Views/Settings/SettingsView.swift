import SwiftUI

struct SettingsView: View {
    @StateObject private var service = MovieService()
    @State private var isTesting = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App header
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(LinearGradient(colors: [.red, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MovieBoxZ")
                                .font(.title2).bold().foregroundColor(.white)
                            Text("Version \(appVersion)")
                                .font(.subheadline).foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(.top, 16)

                    settingsSection(title: "Connection") {
                        HStack {
                            Image(systemName: service.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(service.isConnected ? .green : .red)
                            Text(service.isConnected ? "Connected to backend" : "Cannot reach backend")
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Button {
                                isTesting = true
                                Task { await service.checkConnection(); isTesting = false }
                            } label: {
                                if isTesting { ProgressView().tint(.white) }
                                else { Text("Test").foregroundColor(.red) }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsSection(title: "YouTube") {
                        row(icon: "link", text: "Deep link: youtube:///watch?v=ID")
                        row(icon: "safari", text: "Fallback: SFSafariViewController")
                        row(icon: "checkmark.shield", text: "TOS compliant — no embedding")
                    }

                    settingsSection(title: "About") {
                        row(icon: "doc.text", text: "Privacy Policy")
                        row(icon: "hand.raised", text: "Terms of Service")
                    }

                    settingsSection(title: "Support") {
                        row(icon: "questionmark.circle", text: "Help & FAQ")
                        row(icon: "envelope", text: "Contact Support")
                    }

                    Text("MovieBoxZ is a discovery app. All videos are hosted on YouTube and play in the official YouTube app.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 8)
                        .padding(.bottom, 60)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
            VStack(spacing: 0) {
                content()
            }
            .padding(14)
            .background(Color.white.opacity(0.07))
            .cornerRadius(10)
        }
    }

    private func row(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.red).frame(width: 20)
            Text(text).font(.system(size: 15)).foregroundColor(.white.opacity(0.8))
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
