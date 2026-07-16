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

    #if os(tvOS)
    @State private var showRegionPicker = false
    #endif

    // Drives the in-app legal document pop-ups.
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

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
    private let helpURL = URL(string: "https://movieboxz.com")!
    private let supportEmail = "support@movieboxz.com"

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        iosBody
        #endif
    }

    // MARK: - iOS Body (unchanged)

    #if os(iOS)
    private var iosBody: some View {
        NavigationStack {
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
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }

                // MARK: About
                Section("About") {
                    Button {
                        showPrivacyPolicy = true
                    } label: {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.primary)
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showTermsOfService = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.primary)
                            Text("Terms of Service")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
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
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentView(title: "Privacy Policy", text: LegalContent.privacyPolicy)
        }
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentView(title: "Terms of Service", text: LegalContent.termsOfService)
        }
    }
    #endif

    // MARK: - tvOS Body (ZStack + ScrollView, focus escapes to the tab bar)

    #if os(tvOS)
    private var tvBody: some View {
        ZStack {
            Color.mbzInk.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    // Header — lives inside the ScrollView, so it behaves like
                    // every other tab (no NavigationView title trap / sticky).
                    HStack(spacing: 14) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 56 * 0.7))
                            .foregroundColor(.mbzGold)
                        Text("Settings")
                            .font(.system(size: 56, weight: .heavy))
                            .tracking(0.5)
                            .foregroundColor(.mbzGold)
                    }

                    tvAppIdentitySection
                    tvAboutSection
                    tvAttributionSection
                    tvSupportSection
                    tvRegionSection
                    tvPrivacySection
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            }
        }
        .fullScreenCover(isPresented: $showRegionPicker) {
            TVRegionPickerView(
                options: Self.regionOptions,
                selection: regionOverride
            ) { code in
                regionOverride = code
                movieService.setRegionOverride(code.isEmpty ? nil : code)
            }
        }
        .fullScreenCover(isPresented: $showPrivacyPolicy) {
            LegalDocumentView(title: "Privacy Policy", text: LegalContent.privacyPolicy)
        }
        .fullScreenCover(isPresented: $showTermsOfService) {
            LegalDocumentView(title: "Terms of Service", text: LegalContent.termsOfService)
        }
    }

    // MARK: - tvOS Section Building Blocks

    /// A titled section: a gold uppercase label above a .mbzSlate rounded card.
    /// Wrapped in .focusSection() so vertical navigation between cards is clean
    /// and pressing Up from the top row reaches the tab bar.
    @ViewBuilder
    private func tvSection<Content: View>(
        _ title: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.mbzGold)
            }
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mbzSlate)
            .cornerRadius(16)
        }
        .focusSection()
    }

    /// Non-focusable informational row: icon + label + optional trailing value
    /// and/or trailing status glyph.
    private func tvInfoRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: String? = nil,
        valueColor: Color = .mbzMuted,
        trailingSystemImage: String? = nil,
        trailingColor: Color = .green
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 30))
            Text(label)
                .font(.system(size: 30))
                .foregroundColor(.mbzScreen)
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 26))
                    .foregroundColor(valueColor)
            }
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .foregroundColor(trailingColor)
                    .font(.system(size: 30))
            }
        }
    }

    /// Focusable link row that opens a URL.
    private func tvLinkButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundColor(.mbzScreen)
                    .font(.system(size: 30))
                Text(label)
                    .foregroundColor(.mbzScreen)
                    .font(.system(size: 30))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 24))
                    .foregroundColor(.mbzMuted)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 12)))
    }

    // MARK: - tvOS Sections

    private var tvAppIdentitySection: some View {
        tvSection(nil) {
            HStack(spacing: 14) {
                Image(systemName: "tv.circle.fill")
                    .foregroundColor(.mbzGold)
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 4) {
                    Text("MovieBoxZ")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.mbzScreen)
                }
                Spacer()
            }
        }
    }

    private var tvAboutSection: some View {
        tvSection("About") {
            tvLinkButton(icon: "shield.checkered", label: "Privacy Policy") {
                showPrivacyPolicy = true
            }
            tvLinkButton(icon: "doc.text", label: "Terms of Service") {
                showTermsOfService = true
            }
        }
    }

    private var tvAttributionSection: some View {
        tvSection("Data Attribution") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Movie & TV metadata and artwork provided by TMDB.")
                    .font(.system(size: 26))
                    .foregroundColor(.mbzScreen)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.system(size: 22))
                    .foregroundColor(.mbzMuted)
            }

            Text("Ratings provided by OMDb API and IMDb.")
                .font(.system(size: 26))
                .foregroundColor(.mbzScreen)

            Text("Video content is hosted on and streamed from YouTube. MovieBoxZ links to the official YouTube app and does not host, stream, download, or store any video. Playback is subject to YouTube's Terms of Service.")
                .font(.system(size: 22))
                .foregroundColor(.mbzMuted)
        }
    }

    private var tvSupportSection: some View {
        tvSection("Support") {
            tvLinkButton(icon: "questionmark.circle", label: "Help & FAQ") {
                UIApplication.shared.open(helpURL)
            }
            // tvOS: mailto not supported, show email address instead
            tvInfoRow(
                icon: "envelope",
                iconColor: .mbzScreen,
                label: "Contact Support",
                value: supportEmail
            )
        }
    }

    private var tvRegionSection: some View {
        tvSection("Region") {
            Button {
                showRegionPicker = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "globe")
                        .foregroundColor(.mbzGold)
                        .font(.system(size: 30))
                    Text("Region")
                        .font(.system(size: 30))
                        .foregroundColor(.mbzScreen)
                    Spacer()
                    Text(effectiveRegionDescription)
                        .font(.system(size: 26))
                        .foregroundColor(.mbzMuted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.mbzMuted)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 12)))

            Text("Choose which country's catalog to browse. Some movies are only available to watch in certain regions.")
                .font(.system(size: 22))
                .foregroundColor(.mbzMuted)
        }
    }

    private var tvPrivacySection: some View {
        tvSection("Data & Privacy") {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 34))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("No account required")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.mbzScreen)
                    Text("Your favorites and watch history are stored only on this device. MovieBoxZ does not collect personal data or require sign-in.")
                        .font(.system(size: 24))
                        .foregroundColor(.mbzMuted)
                }
            }
        }
    }
    #endif
}

// MARK: - tvOS Region Picker

#if os(tvOS)
/// Full-screen scrollable, focusable list of catalog regions. Presented from
/// the Region row instead of a bare inline Picker, which renders poorly with
/// ~250 countries on tvOS.
private struct TVRegionPickerView: View {
    let options: [RegionOption]
    let selection: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.mbzInk.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    HStack(spacing: 14) {
                        Image(systemName: "globe")
                            .font(.system(size: 56 * 0.7))
                            .foregroundColor(.mbzGold)
                        Text("Region")
                            .font(.system(size: 56, weight: .heavy))
                            .tracking(0.5)
                            .foregroundColor(.mbzGold)
                        Spacer()
                        // Explicit way out — selecting a row isn't the only exit.
                        Button("Close") { dismiss() }
                            .font(.system(size: 28, weight: .semibold))
                            .buttonStyle(FocusBorderButtonStyle(variant: .action(cornerRadius: 10)))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option.code)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(option.name)
                                        .font(.system(size: 30))
                                        .foregroundColor(.mbzScreen)
                                    Spacer()
                                    if option.code == selection {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundColor(.mbzGold)
                                    }
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 12)))
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mbzSlate)
                    .cornerRadius(16)
                    .focusSection()
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            }
        }
        // Menu closes the picker instead of falling through to the system.
        .onExitCommand { dismiss() }
    }
}
#endif

#Preview {
    SettingsView()
        .environmentObject(MovieService())
        .preferredColorScheme(.dark)
}
