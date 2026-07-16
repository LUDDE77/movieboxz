import SwiftUI

struct ContentView: View {
    @State private var selectedTab = ContentView.launchTab
    // Tabs the user has opened at least once. On iOS we keep these views
    // alive (below) so returning to a tab doesn't tear down its @State and
    // re-fetch — which previously showed a spinner and, on a flaky network,
    // an empty list (e.g. "TV Series empty when I come back").
    @State private var visitedTabs: Set<Int> = [ContentView.launchTab]

    // DEBUG-only: open a specific tab at launch (for screenshot automation),
    // e.g. `simctl launch … UI_TAB=1`. Compiled out of Release.
    static var launchTab: Int {
        #if DEBUG
        for arg in CommandLine.arguments where arg.hasPrefix("UI_TAB=") {
            if let n = Int(arg.dropFirst(7)) { return n }
        }
        #endif
        return 0
    }

    var body: some View {
        #if os(tvOS)
        TabView(selection: $selectedTab) {
            MainBrowseView()
                .tabItem {
                    Image(systemName: "tv.fill")
                    Text("Browse")
                }
                .tag(0)

            TVSeriesView()
                .tabItem {
                    Image(systemName: "tv")
                    Text("Series")
                }
                .tag(1)

            KidsView()
                .tabItem {
                    Image(systemName: "star.circle.fill")
                    Text("Kids")
                }
                .tag(2)

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .tag(3)

            LibraryView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Library")
                }
                .tag(4)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(5)
        }
        .accentColor(.mbzGold)
        .tabViewStyle(.automatic)
        #else
        iOSLayout
        #endif
    }

    #if os(iOS)
    private var iOSLayout: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Full-screen ink base
                Color.mbzInk

                // Tab content fills the full screen so its own
                // internal .ignoresSafeArea() calls work correctly
                tabContent
                    .frame(width: geo.size.width, height: geo.size.height)

                // Tab bar: fixed height, anchored to the bottom of the screen.
                // It renders over the content (higher z-order in the ZStack).
                CustomTabBar(selectedTab: $selectedTab)
                    .frame(width: geo.size.width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // geo.size == the physical screen (landscape: 852 x 393) so backdrops
        // bleed to every edge. Real safe-area insets are injected at the app
        // root (MovieBoxZApp) as \.contentSafeInsets — see FeaturedMovieBanner.
        .ignoresSafeArea()
        .statusBarHidden()
        .onChange(of: selectedTab) {
            visitedTabs.insert(selectedTab)
        }
    }

    // Keep every already-visited tab in the hierarchy and just show/hide it,
    // so its @State (loaded lists, scroll position) survives tab switches.
    // Tabs are still lazily created on first visit, so we don't fire six
    // network loads at launch.
    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                if visitedTabs.contains(index) {
                    tabView(for: index)
                        .opacity(selectedTab == index ? 1 : 0)
                        .allowsHitTesting(selectedTab == index)
                        .accessibilityHidden(selectedTab != index)
                }
            }
        }
    }

    @ViewBuilder
    private func tabView(for index: Int) -> some View {
        switch index {
        case 0: MainBrowseView()
        case 1: TVSeriesView()
        case 2: KidsView()
        case 3: SearchView()
        case 4: LibraryView()
        default: SettingsView()
        }
    }
    #endif
}

// Real safe-area insets injected from the top level (where they aren't zeroed
// by .ignoresSafeArea()), so screens can keep text/controls clear of the notch
// in landscape while backdrops bleed edge-to-edge. Defined for both platforms
// (defaults to zero); only iOS injects real values, tvOS just reads zero.
struct ContentSafeInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}
extension EnvironmentValues {
    var contentSafeInsets: EdgeInsets {
        get { self[ContentSafeInsetsKey.self] }
        set { self[ContentSafeInsetsKey.self] = newValue }
    }
}

/// Carries the real safe-area insets up from a background reader so we can
/// inject them WITHOUT bounding the content (a GeometryReader wrapper would
/// clip the fullscreen backdrop to the safe area, leaving a black strip).
struct SafeInsetsPreferenceKey: PreferenceKey {
    static let defaultValue = EdgeInsets()
    static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
        value = nextValue()
    }
}

#if os(iOS)
private struct CustomTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, label: String)] = [
        ("tv.fill",          "Browse"),
        ("tv",               "TV Series"),
        ("star.circle.fill", "Kids"),
        ("magnifyingglass",  "Search"),
        ("heart.fill",       "Library"),
        ("gearshape.fill",   "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    if selectedTab != index {
                        HapticFeedback.selection()
                    }
                    selectedTab = index
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20))
                        Text(tabs[index].label)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(selectedTab == index ? .mbzGold : .mbzMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.mbzInk.opacity(0.92))
    }
}
#endif

#Preview {
    ContentView()
        .environmentObject(MovieService())
}
