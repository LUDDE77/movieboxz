import SwiftUI
import UIKit

/// A selectable country for the Region override picker.
private struct RegionOption: Identifiable, Hashable {
    let code: String   // ISO 3166-1 alpha-2, e.g. "US". Empty string == Auto.
    let name: String
    var id: String { code }
}

struct SettingsView: View {
    @EnvironmentObject private var movieService: MovieService
    @State private var isConnected = false

    // Bound to the persisted override. Empty string means "Auto (detected)".
    @AppStorage("regionOverride") private var regionOverride: String = ""

    /// All selectable countries: "Auto" first, then every 2-letter region
    /// sorted by localized name.
    private static let regionOptions: [RegionOption] = {
        var options = Locale.Region.isoRegions
            .map { $0.identifier }
            .filter { $0.count == 2 }
            .map { code -> RegionOption in
                let name = Locale.current.localizedString(forRegionCode: code) ?? code
                return RegionOption(code: code, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        options.insert(RegionOption(code: "", name: "Auto (detected)"), at: 0)
        return options
    }()

    /// A human-readable description of the currently effective region.
    private var effectiveRegionDescription: String {
        if let override = movieService.regionOverrideCode {
            let name = Locale.current.localizedString(forRegionCode: override) ?? override
            return name
        }
        if let detected = Locale.current.region?.identifier {
            return "Auto (\(detected))"
        }
        return "Auto"
    }

    // MARK: - Update these URLs when web pages are live
    private let privacyPolicyURL = URL(string: "https://movieboxz.app/privacy")!
    private let termsOfServiceURL = URL(string: "https://movieboxz.app/terms")!
    private let helpURL = URL(string: "https://movieboxz.app/help")!
    private let supportEmail = "support@movieboxz.app"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            List {
                // MARK: App Identity
                Section {
                    HStack {
                        Image(systemName: "tv.circle.fill")
                            .foregroundColor(.mbzGold)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("MovieBoxZ")
                                .font(.headline)
                            Text(appVersion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }

                // MARK: Connection
                Section("Connection") {
                    HStack {
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isConnected ? .green : .red)
                        Text("Backend Service")
                        Spacer()
                        Text(isConnected ? "Connected" : "Offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Test Connection") {
                        movieService.checkConnection()
                    }
                }

                // MARK: YouTube Integration
                Section("YouTube Integration") {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                        Text("Deep Link to YouTube")
                        Spacer()
                        Text("Enabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "tv")
                            .foregroundColor(.blue)
                        Text("Apple TV YouTube")
                        Spacer()
                        Text("Supported")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: About
                Section("About") {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("YouTube Terms Compliance")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Button {
                        UIApplication.shared.open(privacyPolicyURL)
                    } label: {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.primary)
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        UIApplication.shared.open(termsOfServiceURL)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.primary)
                            Text("Terms of Service")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: Attribution (required by data providers' terms)
                Section("Data Attribution") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Movie & TV metadata and artwork provided by TMDB.")
                            .font(.footnote)
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)

                    Text("Ratings provided by OMDb API and IMDb.")
                        .font(.footnote)

                    Text("Video content is hosted on and streamed from YouTube. MovieBoxZ links to the official YouTube app and does not host, stream, download, or store any video. Playback is subject to YouTube's Terms of Service.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                }

                // MARK: Support
                Section("Support") {
                    Button {
                        UIApplication.shared.open(helpURL)
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.primary)
                            Text("Help & FAQ")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    #if os(iOS)
                    Button {
                        if let mailURL = URL(string: "mailto:\(supportEmail)") {
                            UIApplication.shared.open(mailURL)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.primary)
                            Text("Contact Support")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    #else
                    // tvOS: mailto not supported, show email address instead
                    HStack {
                        Image(systemName: "envelope")
                        Text("Contact Support")
                        Spacer()
                        Text(supportEmail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    #endif
                }

                // MARK: Region
                Section("Region") {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.mbzGold)
                        Text("Region")
                        Spacer()
                        Text(effectiveRegionDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Catalog Region", selection: $regionOverride) {
                        ForEach(Self.regionOptions) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #endif
                    .onChange(of: regionOverride) { _, newValue in
                        movieService.setRegionOverride(newValue.isEmpty ? nil : newValue)
                    }

                    Text("Choose which country's catalog to browse. Some movies are only available to watch in certain regions.")
                        .font(.caption)
                        .foregroundColor(.mbzMuted)
                }

                // MARK: Privacy Notice
                Section("Data & Privacy") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No account required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Your favorites and watch history are stored only on this device. MovieBoxZ does not collect personal data or require sign-in.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            .background(Color.mbzInk)
            #endif
            .navigationTitle("Settings")
        }
        .onReceive(movieService.$isConnected) { connected in
            isConnected = connected
        }
        .onAppear {
            isConnected = movieService.isConnected
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(MovieService())
        .preferredColorScheme(.dark)
}
