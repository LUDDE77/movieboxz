import SwiftUI

// MARK: - Series Matching Wizard
//
// 1. Pick a channel (series channels are hinted)
// 2. Pick/create the tv_series involved + fetch each one's TMDB episode guide
// 3. Run a dry-run match (POST match-episodes) and review proposals
// 4. Confirm the checked matches (POST confirm-episode-matches)

private enum MatchWizardStep: Int, CaseIterable {
    case channel = 1
    case series = 2
    case review = 3
    case confirm = 4

    var title: String {
        switch self {
        case .channel: return "Channel"
        case .series: return "Series & Guides"
        case .review: return "Review Matches"
        case .confirm: return "Confirm"
        }
    }
}

/// Episode-guide status for one series in step 2.
private enum GuideState: Equatable {
    case loading
    case missing
    case loaded(episodes: Int)
    case failed(String)
}

struct SeriesMatchingView: View {
    @StateObject private var apiService = AdminAPIService()

    @State private var step: MatchWizardStep = .channel

    // Step 1: channel
    @State private var channels: [ChannelWithPattern] = []
    @State private var isLoadingChannels = false
    @State private var channelsError: String?
    @State private var selectedChannelId: String?

    // Step 2: series + guides
    @State private var seriesList: [TvSeries] = []
    @State private var isLoadingSeries = false
    @State private var seriesError: String?
    @State private var selectedSeriesIds: Set<String> = []
    @State private var guideStates: [String: GuideState] = [:]
    @State private var tmdbIdInputs: [String: String] = [:]
    @State private var fetchingGuides: Set<String> = []
    @State private var seriesSearch = ""

    // Create series
    @State private var showCreateSeriesSheet = false
    @State private var newSeriesTitle = ""
    @State private var isCreatingSeries = false
    @State private var createSeriesError: String?

    // Step 3: dry-run results
    @State private var isMatching = false
    @State private var matchError: String?
    @State private var proposals: [EpisodeMatchProposal] = []
    @State private var unmatched: [EpisodeMatchUnmatched] = []
    @State private var checkedProposalIds: Set<String> = []

    // Step 4: confirm results
    @State private var isConfirming = false
    @State private var confirmError: String?
    @State private var confirmResult: EpisodeMatchConfirmData?

    private var selectedChannel: ChannelWithPattern? {
        channels.first { $0.id == selectedChannelId }
    }

    private var seriesById: [String: TvSeries] {
        Dictionary(uniqueKeysWithValues: seriesList.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider()

            Group {
                switch step {
                case .channel: channelStep
                case .series: seriesStep
                case .review: reviewStep
                case .confirm: confirmStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            navigationBar
        }
        .navigationTitle("Series Matching")
        .task {
            await loadChannels()
        }
        .sheet(isPresented: $showCreateSeriesSheet) {
            createSeriesSheet
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 16) {
            ForEach(MatchWizardStep.allCases, id: \.rawValue) { s in
                HStack(spacing: 6) {
                    Text("\(s.rawValue)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 20, height: 20)
                        .background(s == step ? Color.accentColor : (s.rawValue < step.rawValue ? Color.green : Color.gray.opacity(0.3)))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                    Text(s.title)
                        .font(.caption)
                        .fontWeight(s == step ? .semibold : .regular)
                        .foregroundColor(s == step ? .primary : .secondary)
                }
                if s != .confirm {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            if let channel = selectedChannel, step != .channel {
                Text(channel.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            if step != .channel {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            Spacer()

            switch step {
            case .channel:
                Button("Next: Pick Series") {
                    step = .series
                    Task { await loadSeries() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedChannelId == nil)

            case .series:
                Button {
                    Task { await runMatching() }
                } label: {
                    if isMatching {
                        ProgressView().controlSize(.small).frame(minWidth: 120)
                    } else {
                        Label("Run Matching (dry run)", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSeriesIds.isEmpty || isMatching)

            case .review:
                Button {
                    Task { await confirmMatches() }
                } label: {
                    if isConfirming {
                        ProgressView().controlSize(.small).frame(minWidth: 120)
                    } else {
                        Label("Confirm \(checkedProposalIds.count) match\(checkedProposalIds.count == 1 ? "" : "es")", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(checkedProposalIds.isEmpty || isConfirming)

            case .confirm:
                Button {
                    Task { await runMatching() }
                } label: {
                    Label("Re-run Matching", systemImage: "arrow.clockwise")
                }
                Button("Start Over") {
                    resetWizard()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private func goBack() {
        switch step {
        case .channel: break
        case .series: step = .channel
        case .review: step = .series
        case .confirm: step = .review
        }
    }

    private func resetWizard() {
        step = .channel
        selectedSeriesIds = []
        proposals = []
        unmatched = []
        checkedProposalIds = []
        confirmResult = nil
        matchError = nil
        confirmError = nil
    }

    // MARK: - Step 1: Channel

    private var channelStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pick the channel whose staged episodes you want to match")
                    .font(.headline)
                Text("Tip: use channels marked SERIES — matching runs over the channel's staged movies that are still pending approval.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)

            Divider()

            if isLoadingChannels {
                ProgressView("Loading channels…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let channelsError = channelsError {
                VStack(spacing: 8) {
                    Text("Failed to load channels").font(.headline)
                    Text(channelsError).font(.caption).foregroundColor(.secondary)
                    Button("Retry") { Task { await loadChannels() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedChannelId) {
                    ForEach(sortedChannels) { channel in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let count = channel.videoCount {
                                    Text("\(count) videos")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if channel.hasSeries {
                                StatusBadge(text: "SERIES", color: .purple)
                            }
                            if channel.hasMovies {
                                StatusBadge(text: "MOVIES", color: .blue)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(channel.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    /// Series channels first, then alphabetical.
    private var sortedChannels: [ChannelWithPattern] {
        channels.sorted {
            if $0.hasSeries != $1.hasSeries { return $0.hasSeries }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Step 2: Series + guides

    private var seriesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select the TV series that appear on this channel")
                        .font(.headline)
                    Text("Each selected series needs an episode guide for title matching — fetch one from TMDB below if missing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    showCreateSeriesSheet = true
                } label: {
                    Label("New Series", systemImage: "plus.circle")
                }
            }
            .padding(12)

            HStack {
                TextField("Search series…", text: $seriesSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Text("\(selectedSeriesIds.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            if isLoadingSeries {
                ProgressView("Loading series…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let seriesError = seriesError {
                VStack(spacing: 8) {
                    Text("Failed to load series").font(.headline)
                    Text(seriesError).font(.caption).foregroundColor(.secondary)
                    Button("Retry") { Task { await loadSeries() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredSeries) { series in
                        seriesRow(series)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var filteredSeries: [TvSeries] {
        let query = seriesSearch.trimmingCharacters(in: .whitespaces)
        // Selected series always stay visible on top.
        let matches = query.isEmpty
            ? seriesList
            : seriesList.filter { $0.title.localizedCaseInsensitiveContains(query) || selectedSeriesIds.contains($0.id) }
        return matches.sorted {
            let aSel = selectedSeriesIds.contains($0.id)
            let bSel = selectedSeriesIds.contains($1.id)
            if aSel != bSel { return aSel }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func seriesRow(_ series: TvSeries) -> some View {
        let isSelected = selectedSeriesIds.contains(series.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    toggleSeries(series)
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Text(series.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let imdbId = series.imdbId {
                    Text(imdbId)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    guideStatusBadge(for: series.id)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleSeries(series) }

            // Inline guide controls for selected series
            if isSelected {
                HStack(spacing: 8) {
                    Spacer().frame(width: 26)

                    TextField("TMDB TV show ID", text: tmdbBinding(for: series.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)

                    Button {
                        Task { await fetchGuide(for: series.id) }
                    } label: {
                        if fetchingGuides.contains(series.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Fetch Episode Guide", systemImage: "square.and.arrow.down")
                                .font(.caption)
                        }
                    }
                    .disabled(Int(tmdbBinding(for: series.id).wrappedValue.trimmingCharacters(in: .whitespaces)) == nil
                              || fetchingGuides.contains(series.id))

                    if case .failed(let message) = guideStates[series.id] {
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }

                    Spacer()
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func guideStatusBadge(for seriesId: String) -> some View {
        switch guideStates[seriesId] {
        case .loading:
            ProgressView().controlSize(.small)
        case .loaded(let episodes):
            StatusBadge(text: "Guide: \(episodes) episodes", color: .green)
        case .missing:
            StatusBadge(text: "No guide", color: .orange)
        case .failed:
            StatusBadge(text: "Guide error", color: .red)
        case nil:
            EmptyView()
        }
    }

    private func tmdbBinding(for seriesId: String) -> Binding<String> {
        Binding(
            get: { tmdbIdInputs[seriesId] ?? "" },
            set: { tmdbIdInputs[seriesId] = $0 }
        )
    }

    private func toggleSeries(_ series: TvSeries) {
        if selectedSeriesIds.contains(series.id) {
            selectedSeriesIds.remove(series.id)
        } else {
            selectedSeriesIds.insert(series.id)
            if guideStates[series.id] == nil {
                Task { await checkGuide(for: series.id) }
            }
        }
    }

    // MARK: - Step 3: Review proposals

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review proposed episode matches (dry run — nothing saved yet)")
                        .font(.headline)
                    Text("\(proposals.count) proposal\(proposals.count == 1 ? "" : "s"), \(unmatched.count) unmatched. Rows with confidence ≥ 70% are pre-checked.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Check All") { checkedProposalIds = Set(proposals.map(\.id)) }
                Button("Uncheck All") { checkedProposalIds = [] }
            }
            .padding(12)

            if let matchError = matchError {
                Text(matchError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            if proposals.isEmpty && unmatched.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No pending staged movies to match on this channel")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !proposals.isEmpty {
                        Section("Proposals (\(proposals.count))") {
                            proposalHeader
                            ForEach(proposals) { proposal in
                                proposalRow(proposal)
                            }
                        }
                    }
                    if !unmatched.isEmpty {
                        Section("Unmatched (\(unmatched.count))") {
                            ForEach(unmatched) { row in
                                HStack(alignment: .top) {
                                    Text(row.youtubeTitle ?? "Unknown video")
                                        .font(.caption)
                                        .lineLimit(2)
                                    Spacer()
                                    Text(row.reason ?? "No reason")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var proposalHeader: some View {
        HStack(spacing: 8) {
            Text("").frame(width: 24)
            Text("YouTube Title").font(.caption2).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Series").font(.caption2).foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            Text("S/E").font(.caption2).foregroundColor(.secondary)
                .frame(width: 55, alignment: .leading)
            Text("Episode Name").font(.caption2).foregroundColor(.secondary)
                .frame(width: 170, alignment: .leading)
            Text("Conf.").font(.caption2).foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func proposalRow(_ proposal: EpisodeMatchProposal) -> some View {
        let isChecked = checkedProposalIds.contains(proposal.id)
        let confidence = proposal.confidence ?? 0

        return HStack(spacing: 8) {
            Button {
                if isChecked {
                    checkedProposalIds.remove(proposal.id)
                } else {
                    checkedProposalIds.insert(proposal.id)
                }
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24)

            Text(proposal.youtubeTitle)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(proposal.youtubeTitle)

            Text(seriesById[proposal.tvSeriesId]?.title ?? "Unknown series")
                .font(.caption)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(seasonEpisodeLabel(proposal))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 55, alignment: .leading)

            Text(proposal.episodeName ?? "—")
                .font(.caption)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
                .help(proposal.episodeName ?? "")

            Text("\(Int(confidence))%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(confidenceColor(confidence))
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    private func seasonEpisodeLabel(_ proposal: EpisodeMatchProposal) -> String {
        guard let season = proposal.season, let episode = proposal.episode else { return "—" }
        return "S\(season)E\(episode)"
    }

    // MARK: - Step 4: Confirm results

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = confirmResult {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Applied \(result.updated) episode match\(result.updated == 1 ? "" : "es")")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Season/episode/series were written to the channel's staged movies.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let errors = result.errors, !errors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(errors.count) error\(errors.count == 1 ? "" : "s")")
                            .font(.headline)
                            .foregroundColor(.red)
                        List(errors, id: \.self) { error in
                            HStack {
                                Text(error.stagedMovieId ?? "—")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(error.error ?? "Unknown error")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }

                Text("Re-run matching to process remaining unmatched videos, or start over with another channel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let confirmError = confirmError {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                    Text("Confirmation failed").font(.headline)
                    Text(confirmError).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Create series sheet

    private var createSeriesSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New TV Series")
                .font(.title2)
                .fontWeight(.bold)

            TextField("Series title", text: $newSeriesTitle)
                .textFieldStyle(.roundedBorder)

            if let createSeriesError = createSeriesError {
                Text(createSeriesError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    showCreateSeriesSheet = false
                    newSeriesTitle = ""
                    createSeriesError = nil
                }
                Spacer()
                Button {
                    Task { await createSeries() }
                } label: {
                    if isCreatingSeries {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create & Select")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newSeriesTitle.trimmingCharacters(in: .whitespaces).isEmpty || isCreatingSeries)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    // MARK: - Data loading / actions

    private func loadChannels() async {
        isLoadingChannels = true
        channelsError = nil
        do {
            let data = try await apiService.getChannelsWithPatterns()
            channels = data.channels
        } catch {
            channelsError = error.localizedDescription
        }
        isLoadingChannels = false
    }

    private func loadSeries() async {
        guard seriesList.isEmpty else { return }
        isLoadingSeries = true
        seriesError = nil
        do {
            seriesList = try await apiService.fetchAllTvSeries()
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch {
            seriesError = error.localizedDescription
        }
        isLoadingSeries = false
    }

    private func checkGuide(for seriesId: String) async {
        guideStates[seriesId] = .loading
        do {
            if let guide = try await apiService.getEpisodeGuide(seriesId: seriesId) {
                guideStates[seriesId] = .loaded(episodes: guide.episodes.count)
                if tmdbIdInputs[seriesId]?.isEmpty != false, let sourceId = guide.sourceId {
                    tmdbIdInputs[seriesId] = sourceId
                }
            } else {
                guideStates[seriesId] = .missing
            }
        } catch {
            guideStates[seriesId] = .failed(error.localizedDescription)
        }
    }

    private func fetchGuide(for seriesId: String) async {
        guard let tmdbId = Int((tmdbIdInputs[seriesId] ?? "").trimmingCharacters(in: .whitespaces)) else { return }
        fetchingGuides.insert(seriesId)
        do {
            let result = try await apiService.fetchEpisodeGuideFromTMDB(seriesId: seriesId, tmdbId: tmdbId)
            guideStates[seriesId] = .loaded(episodes: result.episodesCount)
        } catch {
            guideStates[seriesId] = .failed(error.localizedDescription)
        }
        fetchingGuides.remove(seriesId)
    }

    private func createSeries() async {
        isCreatingSeries = true
        createSeriesError = nil
        do {
            let series = try await apiService.createAdminTVSeries(
                title: newSeriesTitle.trimmingCharacters(in: .whitespaces),
                imdbId: nil,
                description: nil
            )
            seriesList.append(series)
            seriesList.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            selectedSeriesIds.insert(series.id)
            guideStates[series.id] = .missing
            showCreateSeriesSheet = false
            newSeriesTitle = ""
        } catch {
            createSeriesError = error.localizedDescription
        }
        isCreatingSeries = false
    }

    private func runMatching() async {
        guard let channelId = selectedChannelId, !selectedSeriesIds.isEmpty else { return }
        isMatching = true
        matchError = nil
        confirmResult = nil
        confirmError = nil
        do {
            let data = try await apiService.matchEpisodes(channelId: channelId, seriesIds: Array(selectedSeriesIds))
            proposals = data.proposals.sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
            unmatched = data.unmatched
            checkedProposalIds = Set(proposals.filter { ($0.confidence ?? 0) >= 70 }.map(\.id))
            step = .review
        } catch {
            matchError = error.localizedDescription
            if step == .confirm { step = .review }
        }
        isMatching = false
    }

    private func confirmMatches() async {
        guard let channelId = selectedChannelId else { return }
        let matches = proposals
            .filter { checkedProposalIds.contains($0.id) }
            .map {
                EpisodeMatchConfirmation(
                    stagedMovieId: $0.stagedMovieId,
                    tvSeriesId: $0.tvSeriesId,
                    season: $0.season,
                    episode: $0.episode,
                    episodeName: $0.episodeName
                )
            }
        guard !matches.isEmpty else { return }

        isConfirming = true
        confirmError = nil
        do {
            confirmResult = try await apiService.confirmEpisodeMatches(channelId: channelId, matches: matches)
            step = .confirm
        } catch {
            confirmError = error.localizedDescription
            step = .confirm
        }
        isConfirming = false
    }

    // MARK: - Helpers

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 85...: return .green
        case 70..<85: return .orange
        default: return .red
        }
    }
}

#Preview {
    SeriesMatchingView()
}
