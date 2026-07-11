import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: Tab = .browse

    private let tabBarHeight: CGFloat = 52

    enum Tab: Int, CaseIterable {
        case browse, tvSeries, kids, search, library, settings
        var icon: String {
            switch self {
            case .browse:   return "tv.fill"
            case .tvSeries: return "tv"
            case .kids:     return "star.circle.fill"
            case .search:   return "magnifyingglass"
            case .library:  return "heart.fill"
            case .settings: return "gearshape.fill"
            }
        }
        var label: String {
            switch self {
            case .browse:   return "Browse"
            case .tvSeries: return "TV Series"
            case .kids:     return "Kids"
            case .search:   return "Search"
            case .library:  return "Library"
            case .settings: return "Settings"
            }
        }
    }

    private var screenWidth: CGFloat {
        let w = UIScreen.main.bounds.width, h = UIScreen.main.bounds.height
        let v = max(w, h)
        return v > 0 ? v : 852
    }
    private var screenHeight: CGFloat {
        let w = UIScreen.main.bounds.width, h = UIScreen.main.bounds.height
        let v = min(w, h)
        return v > 0 ? v : 393
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            tabContent(
                width: screenWidth,
                height: screenHeight - tabBarHeight
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, tabBarHeight)

            bottomBar
        }
        .frame(width: screenWidth, height: screenHeight)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func tabContent(width: CGFloat, height: CGFloat) -> some View {
        switch selectedTab {
        case .browse:   BrowseView(contentWidth: width, contentHeight: height)
        case .tvSeries: TVSeriesView()
        case .kids:     KidsView()
        case .search:   SearchView()
        case .library:  LibraryView()
        case .settings: SettingsView()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .frame(height: tabBarHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.85))
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
            HapticFeedback.selection()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .red : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
