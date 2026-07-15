import SwiftUI

struct TVSeriesView: View {
    @EnvironmentObject private var movieService: MovieService
    @State private var seriesList: [TVSeries] = []
    @State private var isLoading = true
    @State private var selectedSeries: TVSeries?

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 245, maximum: 245), spacing: 40)]
    private let titleSize: CGFloat = 56
    private let cardTitleSize: CGFloat = 31
    private let cardMetadataSize: CGFloat = 25
    private let cardBadgeSize: CGFloat = 22
    private let cardWidth: CGFloat = 245
    #else
    private let columns = [GridItem(.adaptive(minimum: 126, maximum: 180), spacing: 15)]
    private let titleSize: CGFloat = 28
    private let cardTitleSize: CGFloat = 14
    private let cardMetadataSize: CGFloat = 12
    private let cardBadgeSize: CGFloat = 10
    private let cardWidth: CGFloat = 150
    #endif

    var body: some View {
        ZStack {
            Color.mbzInk.ignoresSafeArea()

            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerView

                        if seriesList.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, spacing: 40) {
                                ForEach(seriesList) { series in
                                    seriesCard(series)
                                }
                            }
                            #if os(tvOS)
                            .padding(.horizontal, 80)
                            .padding(.bottom, 100)
                            #else
                            .padding(.horizontal, 16)
                            .padding(.bottom, 60)
                            #endif
                        }
                    }
                }
            }
        }
        .onAppear {
            // Load on first appear or if a previous load failed (list empty).
            // A populated list is never reloaded, so returning to this tab can't
            // blank it — and loadData only overwrites on success anyway.
            if seriesList.isEmpty { loadData() }
        }
        #if os(tvOS)
        .fullScreenCover(item: $selectedSeries) { series in
            SeriesDetailView(series: series)
        }
        #else
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series)
        }
        #endif
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: "tv")
                .font(.system(size: titleSize * 0.7))
                .foregroundColor(.mbzGold)
            VStack(alignment: .leading, spacing: 4) {
                Text("TV Series")
                    .font(.system(size: titleSize, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(.mbzGold)
                Text("\(seriesList.count) shows")
                    .font(.system(size: cardMetadataSize + 2))
                    .foregroundColor(.mbzMuted)
            }
        }
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.top, 60)
        #else
        .padding(.horizontal, 16)
        .padding(.top, 20)
        #endif
    }

    // MARK: - Series Card

    @ViewBuilder
    private func seriesCard(_ series: TVSeries) -> some View {
        #if os(tvOS)
        Button {
            selectedSeries = series
        } label: {
            seriesCardContent(series)
        }
        .buttonStyle(FocusBorderButtonStyle())
        .accessibilityLabel(seriesAccessibilityLabel(series))
        .accessibilityHint("Double tap to browse episodes")
        #else
        Button {
            selectedSeries = series
        } label: {
            seriesCardContent(series)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seriesAccessibilityLabel(series))
        .accessibilityHint("Tap to browse episodes")
        #endif
    }

    private func seriesCardContent(_ series: TVSeries) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Poster
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: series.posterURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(2/3, contentMode: .fill)
                            .shimmer()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    case .failure:
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .aspectRatio(2/3, contentMode: .fill)
                            VStack(spacing: 8) {
                                Image(systemName: "tv")
                                    .font(.system(size: cardTitleSize + 8))
                                    .foregroundColor(.gray)
                                Text("No Poster")
                                    .font(.system(size: cardBadgeSize))
                                    .foregroundColor(.gray)
                            }
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(10)
                .clipped()

                // Episode count badge — top-right corner
                if let eps = series.episodeCount, eps > 0 {
                    Text("\(eps) Episodes")
                        .font(.system(size: cardBadgeSize, weight: .bold))
                        .foregroundColor(.mbzInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.mbzGold)
                        .cornerRadius(6)
                        .padding(6)
                }
            }

            // Title
            Text(series.title)
                .font(.system(size: cardTitleSize, weight: .semibold))
                .foregroundColor(.mbzScreen)
                .lineLimit(2)

            // Metadata line: year range + season count
            HStack(spacing: 6) {
                if let start = series.yearStart {
                    let endText = series.yearEnd.map { "–\($0)" } ?? "–"
                    Text("\(start)\(endText)")
                        .font(.system(size: cardMetadataSize))
                        .foregroundColor(.mbzMuted)
                }

                if let sc = series.seasonCount, sc > 0 {
                    if series.yearStart != nil {
                        Text("·")
                            .font(.system(size: cardMetadataSize))
                            .foregroundColor(.mbzMuted.opacity(0.6))
                    }
                    Text(sc == 1 ? "1 Season" : "\(sc) Seasons")
                        .font(.system(size: cardMetadataSize))
                        .foregroundColor(.mbzMuted)
                }
            }
        }
    }

    private func seriesAccessibilityLabel(_ series: TVSeries) -> String {
        var parts = [series.title]
        if let sc = series.seasonCount { parts.append("\(sc) season\(sc == 1 ? "" : "s")") }
        if let ec = series.episodeCount { parts.append("\(ec) episode\(ec == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.mbzGold)
                #if os(tvOS)
                .scaleEffect(2)
                #else
                .scaleEffect(1.5)
                #endif
            Text("Loading TV Series...")
                .font(.system(size: cardTitleSize))
                .foregroundColor(.mbzMuted)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "tv")
                #if os(tvOS)
                .font(.system(size: 100))
                #else
                .font(.system(size: 60))
                #endif
                .foregroundColor(.mbzMuted.opacity(0.5))
            Text("No TV Series Yet")
                .font(.system(size: cardTitleSize + 4, weight: .semibold))
                .foregroundColor(.mbzMuted)
            Text("TV series will appear here as they are added")
                .font(.system(size: cardMetadataSize + 2))
                .foregroundColor(.mbzMuted.opacity(0.7))
                .multilineTextAlignment(.center)
                #if os(tvOS)
                .padding(.horizontal, 200)
                #else
                .padding(.horizontal, 40)
                #endif
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        Task {
            isLoading = true
            // Only replace the list on a successful fetch — a transient failure
            // or a request cancelled during a tab transition must NOT blank a
            // list we were just showing.
            if let series = try? await movieService.fetchAllSeries() {
                seriesList = series
            }
            isLoading = false
        }
    }
}
