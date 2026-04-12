import SwiftUI

// MARK: - Series Detail View
// Netflix-style series detail page showing season/episode breakdown.

struct SeriesDetailView: View {
    let series: TVSeries

    @StateObject private var movieService = MovieService()
    @Environment(\.dismiss) private var dismiss

    @State private var seasons: [SeriesSeason] = []
    @State private var seriesDetail: TVSeriesDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedEpisode: Movie?
    @State private var selectedSeasonIndex: Int = 0

    // MARK: Platform sizes

    #if os(tvOS)
    private let titleSize: CGFloat = 48
    private let bodySize: CGFloat = 28
    private let captionSize: CGFloat = 24
    private let sectionHeaderSize: CGFloat = 36
    private let episodeCardWidth: CGFloat = 320
    private let episodeCardHeight: CGFloat = 180
    private let episodeTitleSize: CGFloat = 26
    private let episodeBadgeSize: CGFloat = 22
    private let posterWidth: CGFloat = 280
    private let posterHeight: CGFloat = 420
    private let headerPadding: CGFloat = 80
    private let contentPadding: CGFloat = 80
    private let seasonPickerHeight: CGFloat = 70
    #else
    private let titleSize: CGFloat = 20
    private let bodySize: CGFloat = 14
    private let captionSize: CGFloat = 12
    private let sectionHeaderSize: CGFloat = 16
    private let episodeCardWidth: CGFloat = 160
    private let episodeCardHeight: CGFloat = 90
    private let episodeTitleSize: CGFloat = 12
    private let episodeBadgeSize: CGFloat = 10
    private let posterWidth: CGFloat = 120
    private let posterHeight: CGFloat = 180
    private let headerPadding: CGFloat = 16
    private let contentPadding: CGFloat = 16
    private let seasonPickerHeight: CGFloat = 44
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                mainContent
            }
        }
        .onAppear { loadSeriesDetail() }
        #if os(tvOS)
        .fullScreenCover(item: $selectedEpisode) { MovieDetailView(movie: $0) }
        .onExitCommand { dismiss() }
        #else
        .sheet(item: $selectedEpisode) { MovieDetailView(movie: $0) }
        #endif
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Close button row (tvOS has dedicated close; iOS uses sheet dismiss)
                #if os(tvOS)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(18)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.horizontal, headerPadding)
                .padding(.bottom, 16)
                #endif

                // Header: poster + info
                headerSection

                // Season picker + episodes
                if !seasons.isEmpty {
                    episodeSection
                }
            }
        }
        .background(Color.black)
        #if !os(tvOS)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.9))
                    .background(Circle().fill(Color.black.opacity(0.4)).frame(width: 40, height: 40))
            }
            .padding(.top, 50)
            .padding(.trailing, 16)
        }
        .ignoresSafeArea(edges: .top)
        #endif
    }

    // MARK: - Header Section

    private var headerSection: some View {
        #if os(tvOS)
        HStack(alignment: .top, spacing: 40) {
            // Poster
            posterImage
                .frame(width: posterWidth, height: posterHeight)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.6), radius: 30, y: 10)

            // Series info
            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: 20)

                Text(seriesDetail?.title ?? series.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(3)

                seriesMetaBadges

                if let description = seriesDetail?.description ?? series.description {
                    Text(description)
                        .font(.system(size: bodySize))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(5)
                        .lineSpacing(5)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, headerPadding)
        .padding(.bottom, 40)
        #else
        // iOS: backdrop fill + poster + info overlay, wrapped in a VStack for proper layout
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                // Backdrop from series poster
                AsyncImage(url: series.posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()

                // Gradient overlay
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.5), location: 0.5),
                        .init(color: Color.black, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)

                HStack(alignment: .bottom, spacing: 12) {
                    posterImage
                        .frame(width: posterWidth, height: posterHeight)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.5), radius: 10)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(seriesDetail?.title ?? series.title)
                            .font(.system(size: titleSize, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .shadow(radius: 6)

                        seriesMetaBadges
                    }
                    .padding(.bottom, 8)

                    Spacer()
                }
                .padding(.horizontal, headerPadding)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)

            // Description below the hero on iOS
            if let description = seriesDetail?.description ?? series.description {
                Text(description)
                    .font(.system(size: bodySize))
                    .foregroundColor(.white.opacity(0.8))
                    .lineSpacing(4)
                    .padding(.horizontal, contentPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
        }
        #endif
    }

    private var seriesMetaBadges: some View {
        HStack(spacing: 10) {
            // Year range
            let yearText: String = {
                if let start = seriesDetail?.yearStart ?? series.yearStart {
                    if let end = seriesDetail?.yearEnd ?? series.yearEnd {
                        return "\(start)–\(end)"
                    }
                    return "\(start)–"
                }
                return ""
            }()
            if !yearText.isEmpty {
                metaBadge(yearText, color: .white.opacity(0.15))
            }

            // Season count
            if let seasons = series.seasonCount, seasons > 0 {
                metaBadge(seasons == 1 ? "1 Season" : "\(seasons) Seasons", color: Color.red.opacity(0.25))
            }

            // Episode count
            if let eps = series.episodeCount, eps > 0 {
                metaBadge("\(eps) Episodes", color: .white.opacity(0.12))
            }
        }
    }

    private func metaBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: captionSize, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color)
            .cornerRadius(6)
    }

    @ViewBuilder
    private var posterImage: some View {
        AsyncImage(url: series.posterURL) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2/3, contentMode: .fill)
                    .shimmer()
            case .success(let image):
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            case .failure:
                ZStack {
                    Rectangle().fill(Color.gray.opacity(0.3))
                    Image(systemName: "tv")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
                .aspectRatio(2/3, contentMode: .fill)
            @unknown default:
                EmptyView()
            }
        }
    }

    // MARK: - Episode Section

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Season picker
            if seasons.count > 1 {
                seasonPicker
                    .padding(.horizontal, contentPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
            } else {
                // Single season — just show a header
                Text("Episodes")
                    .font(.system(size: sectionHeaderSize, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, contentPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
            }

            // Episode row for current season
            let currentSeason = selectedSeasonIndex < seasons.count ? seasons[selectedSeasonIndex] : nil
            if let season = currentSeason {
                episodeRow(season: season)
            }
        }
        .padding(.bottom, 60)
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(seasons.indices, id: \.self) { idx in
                    let isSelected = idx == selectedSeasonIndex
                    Button {
                        selectedSeasonIndex = idx
                    } label: {
                        Text("Season \(seasons[idx].seasonNumber)")
                            .font(.system(size: sectionHeaderSize * 0.85, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? .black : .white)
                            .padding(.horizontal, 18)
                            .frame(height: seasonPickerHeight)
                            .background(isSelected ? Color.white : Color.white.opacity(0.15))
                            .cornerRadius(10)
                    }
                    #if os(tvOS)
                    .buttonStyle(FocusBorderButtonStyle(cornerRadius: 10))
                    #else
                    .buttonStyle(.plain)
                    #endif
                }
            }
        }
    }

    private func episodeRow(season: SeriesSeason) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(season.episodes) { episode in
                        episodeCard(episode: episode)
                    }
                }
                .padding(.horizontal, contentPadding)
                .padding(.vertical, 8)
            }
        }
    }

    private func episodeCard(episode: Movie) -> some View {
        #if os(tvOS)
        Button {
            selectedEpisode = episode
        } label: {
            episodeCardContent(episode: episode)
        }
        .buttonStyle(FocusBorderButtonStyle())
        .frame(width: episodeCardWidth)
        .accessibilityLabel(episodeLabel(episode))
        #else
        Button {
            selectedEpisode = episode
        } label: {
            episodeCardContent(episode: episode)
        }
        .buttonStyle(.plain)
        .frame(width: episodeCardWidth)
        .accessibilityLabel(episodeLabel(episode))
        #endif
    }

    private func episodeCardContent(episode: Movie) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: episode.backdropURL ?? episode.posterURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .shimmer()
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        ZStack {
                            Rectangle().fill(Color.gray.opacity(0.3))
                            Image(systemName: "play.rectangle")
                                .font(.system(size: episodeTitleSize + 4))
                                .foregroundColor(.gray)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: episodeCardWidth, height: episodeCardHeight)
                .clipped()
                .cornerRadius(10)

                // Dark gradient at bottom for badge readability
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(width: episodeCardWidth, height: episodeCardHeight)
                .cornerRadius(10)

                // S1E1 badge
                if let season = episode.seasonNumber, let ep = episode.episodeNumber {
                    Text("S\(season)E\(ep)")
                        .font(.system(size: episodeBadgeSize, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(5)
                        .padding(8)
                }

                // Play button hint — subtle overlay
                HStack {
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: episodeTitleSize + 8))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 6)
                        .padding(8)
                }
            }

            // Episode title
            Text(episode.displayTitle)
                .font(.system(size: episodeTitleSize, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(width: episodeCardWidth, alignment: .leading)

            // Runtime
            if episode.runtimeMinutes != nil {
                Text(episode.formattedRuntime)
                    .font(.system(size: episodeBadgeSize + 2))
                    .foregroundColor(.white.opacity(0.5))
            } else if episode.episodeNumber != nil {
                // Show view count as a fallback for episodes without runtime
                Text(episode.formattedViewCount)
                    .font(.system(size: episodeBadgeSize + 2))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func episodeLabel(_ episode: Movie) -> String {
        var parts: [String] = []
        if let s = episode.seasonNumber, let e = episode.episodeNumber {
            parts.append("Season \(s), Episode \(e)")
        }
        parts.append(episode.displayTitle)
        return parts.joined(separator: ". ")
    }

    // MARK: - Loading & Error states

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                #if os(tvOS)
                .scaleEffect(2)
                #else
                .scaleEffect(1.5)
                #endif
            Text("Loading series...")
                .font(.system(size: bodySize))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Could not load series")
                .font(.system(size: titleSize * 0.6, weight: .semibold))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: bodySize))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") { loadSeriesDetail() }
                .font(.system(size: bodySize, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.red)
                .cornerRadius(10)
                #if os(tvOS)
                .buttonStyle(.card)
                #else
                .buttonStyle(.plain)
                #endif
        }
    }

    // MARK: - Data Loading

    private func loadSeriesDetail() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                let detail = try await movieService.fetchSeriesEpisodes(seriesId: series.id)
                seriesDetail = detail.series
                // Map SeasonResponse -> SeriesSeason, sorted by season number
                seasons = detail.seasons
                    .map { SeasonResponse -> SeriesSeason in
                        SeriesSeason(
                            seasonNumber: SeasonResponse.seasonNumber,
                            episodes: SeasonResponse.episodes.sorted {
                                ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0)
                            }
                        )
                    }
                    .sorted { $0.seasonNumber < $1.seasonNumber }
                selectedSeasonIndex = 0
            } catch {
                // Fall back to fetching all TV series episodes by tv_series_id
                await loadEpisodesFallback()
            }
            isLoading = false
        }
    }

    /// Fallback: if the /series/:id/episodes endpoint is not yet available, fetch episodes
    /// from the /movies endpoint filtered by tv_series_id and group them locally.
    private func loadEpisodesFallback() async {
        do {
            let episodes = try await movieService.fetchTVSeries(limit: 200)
            let filtered = episodes.filter { $0.tvSeriesId == series.id }
            if filtered.isEmpty {
                // Show the series with no episodes rather than an error
                seasons = []
                return
            }
            // Group by season number
            var seasonMap: [Int: [Movie]] = [:]
            for ep in filtered {
                let s = ep.seasonNumber ?? 1
                seasonMap[s, default: []].append(ep)
            }
            seasons = seasonMap.map { key, eps in
                SeriesSeason(
                    seasonNumber: key,
                    episodes: eps.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
                )
            }.sorted { $0.seasonNumber < $1.seasonNumber }
            selectedSeasonIndex = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
