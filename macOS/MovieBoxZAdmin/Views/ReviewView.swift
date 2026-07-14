import SwiftUI

// MARK: - Review Screen (below-threshold pick triage)
//
// One movie at a time, big and fast to scan. The operator compares the ORIGINAL
// YouTube video (left) against Our Pick (right) and quickly Approves, Rejects,
// Passes, or re-picks the correct TMDB match.
//
// Keyboard: A = Approve, R = Reject, P = Pass, ←/→ or J/K to move between items.

struct ReviewView: View {
    @StateObject private var apiService = AdminAPIService()

    // Data (accumulated across pages)
    @State private var items: [ReviewMovie] = []
    @State private var channels: [ChannelWithPattern] = []
    @State private var total = 0
    @State private var totalPages = 1
    @State private var nextPage = 1

    // Filter + navigation
    @State private var selectedChannelId = ""
    @State private var currentIndex = 0
    private let pageSize = 50

    // State
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isActing = false

    // Reject sheet
    @State private var showRejectSheet = false
    @State private var rejectReason = ""

    // Re-pick candidates
    @State private var showCandidates = false
    @State private var candidates: [TmdbCandidate] = []
    @State private var candidateQuery = ""
    @State private var isLoadingCandidates = false

    // Direct IMDB id entry
    @State private var imdbInput = ""
    @FocusState private var imdbFieldFocused: Bool

    // Toast
    @State private var toast: ToastMessage?
    @State private var toastDismissTask: Task<Void, Never>?

    // Keyboard focus
    @FocusState private var kbFocused: Bool

    private var currentItem: ReviewMovie? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    /// 1-based position of the item currently on screen within the full queue.
    private var globalPosition: Int {
        guard !items.isEmpty else { return 0 }
        return min(currentIndex + 1, max(total, currentIndex + 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Review")
        .focusable()
        .focusEffectDisabled()
        .focused($kbFocused)
        .onKeyPress { press in handleKeyPress(press) }
        .overlay(alignment: .top) {
            if let toast = toast {
                ToastBannerView(toast: toast) { self.toast = nil }
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showRejectSheet) {
            rejectSheet
        }
        .task {
            await loadChannels()
            await resetAndLoad()
            kbFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Picker("Channel", selection: $selectedChannelId) {
                    Text("All Channels").tag("")
                    ForEach(channels) { channel in
                        Text(channel.title).tag(channel.id)
                    }
                }
                .frame(maxWidth: 280)
                .onChange(of: selectedChannelId) { _, _ in
                    Task { await resetAndLoad() }
                }

                Spacer()

                if let confidence = currentItem?.enrichmentConfidence {
                    StatusBadge(text: "Confidence \(Int(confidence))%", color: confidenceColor(confidence))
                }

                Text(progressLabel)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Button {
                    Task { await resetAndLoad() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            HStack(spacing: 10) {
                keyLegend("A", "Approve")
                keyLegend("R", "Reject")
                keyLegend("P", "Pass")
                keyLegend("← / J", "Prev")
                keyLegend("→ / K", "Next")
                Spacer()
            }
        }
        .padding(12)
    }

    private func keyLegend(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced())
                .fontWeight(.semibold)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.18))
                .cornerRadius(4)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var progressLabel: String {
        guard total > 0 else { return "0 items" }
        return "Reviewing \(globalPosition) of \(total.formatted())"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView("Loading review queue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError = loadError, items.isEmpty {
            VStack(spacing: 8) {
                Text("Failed to load review queue")
                    .font(.headline)
                Text(loadError)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Retry") { Task { await resetAndLoad() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let item = currentItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 20) {
                        originalColumn(item)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        pickColumn(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    actionBar(item)

                    if showCandidates {
                        candidatesStrip(item)
                    }
                }
                .padding(16)
            }
            .id(item.id)   // reset scroll position between items
        } else {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                Text("Nothing left to review")
                    .font(.headline)
                Text("No pending below-threshold picks\(selectedChannelId.isEmpty ? "" : " for this channel").")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Left column: Original (YouTube)

    private func originalColumn(_ item: ReviewMovie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original (YouTube)")
                .font(.headline)

            AsyncImage(url: item.youtubeThumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    ZStack {
                        Color.gray.opacity(0.15)
                        Image(systemName: "photo").foregroundColor(.secondary)
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
            }
            .frame(maxWidth: 420)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.youtubeVideoTitle ?? "Untitled video")
                .font(.title3)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if let channelTitle = item.channelTitle {
                    Label(channelTitle, systemImage: "tv")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let runtime = item.runtimeMinutes {
                    Label("\(runtime) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let url = item.youtubeURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Watch on YouTube ↗", systemImage: "play.rectangle")
                        .font(.callout)
                }
                .buttonStyle(.link)
            }

            Divider()

            Text("YouTube description")
                .font(.subheadline)
                .fontWeight(.semibold)

            ScrollView {
                Text(item.youtubeDescription?.isEmpty == false ? item.youtubeDescription! : "No description available.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
            .frame(maxHeight: 220)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .cornerRadius(8)
        }
    }

    // MARK: - Right column: Our Pick

    private func pickColumn(_ item: ReviewMovie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Our Pick")
                .font(.headline)

            HStack(alignment: .top, spacing: 14) {
                PosterImage(path: item.posterPath, width: 120, height: 180, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title ?? "No title")
                        .font(.title3)
                        .fontWeight(.bold)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        if let year = item.releaseYear {
                            Text(year).font(.callout).foregroundColor(.secondary)
                        }
                        if let runtime = item.runtimeMinutes {
                            Text("· \(runtime) min").font(.callout).foregroundColor(.secondary)
                        }
                    }

                    if let confidence = item.enrichmentConfidence {
                        StatusBadge(text: "Confidence \(Int(confidence))%", color: confidenceColor(confidence))
                    }

                    HStack(spacing: 10) {
                        if let tmdbId = item.tmdbId {
                            Text("TMDB \(tmdbId)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        if let imdbId = item.imdbId, !imdbId.isEmpty {
                            Text(imdbId)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let director = item.director, !director.isEmpty {
                DetailRow(label: "Director", value: director, showColon: true)
            }
            if let actors = item.actors, !actors.isEmpty {
                DetailRow(label: "Cast", value: actors, showColon: true)
            }

            Divider()

            Text("Plot")
                .font(.subheadline)
                .fontWeight(.semibold)

            ScrollView {
                Text(item.description?.isEmpty == false ? item.description! : "No plot available.")
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
            .frame(maxHeight: 160)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .cornerRadius(8)
        }
    }

    // MARK: - Action Bar

    private func actionBar(_ item: ReviewMovie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Task { await approve(item) }
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isActing)
                .help("Approve this pick (A)")

                Button {
                    rejectReason = ""
                    showRejectSheet = true
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isActing)
                .help("Reject this movie (R)")

                Button {
                    pass()
                } label: {
                    Label("Pass", systemImage: "arrow.right.circle")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .disabled(isActing)
                .help("Skip without deciding (P)")

                Spacer()

                Button {
                    Task { await toggleCandidates(item) }
                } label: {
                    Label(showCandidates ? "Hide candidates" : "Wrong match? Find the right one",
                          systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(isActing)
            }

            imdbEntryRow(item)

            HStack(spacing: 12) {
                Button { goPrev() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex == 0 || isActing)

                Button { goNext() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled((currentIndex >= items.count - 1 && nextPage > totalPages) || isActing)

                if isActing {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Direct IMDB entry

    private func imdbEntryRow(_ item: ReviewMovie) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundColor(.secondary)
            Text("Know the IMDB id?")
                .font(.callout)
                .foregroundColor(.secondary)

            TextField("IMDB ID (tt…)", text: $imdbInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .focused($imdbFieldFocused)
                .disabled(isActing)
                .onSubmit {
                    if isValidImdbInput { Task { await applyImdb(item) } }
                }

            Button("Apply") {
                Task { await applyImdb(item) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isActing || !isValidImdbInput)
            .help("Fetch this IMDB id from OMDB and set it as the pick, then Approve")
        }
        .padding(.top, 2)
    }

    /// The normalized tt id from the current field text, or nil if it isn't valid.
    /// Accepts a bare id ("tt1234567") or a pasted IMDB URL/text containing one.
    private var normalizedImdbId: String? {
        Self.extractImdbId(from: imdbInput)
    }

    private var isValidImdbInput: Bool {
        normalizedImdbId != nil
    }

    /// Pull a `tt\d+` id out of arbitrary input (bare id or a full imdb.com URL).
    static func extractImdbId(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Match the first tt-id anywhere in the string (handles pasted URLs).
        if let range = trimmed.range(of: "tt[0-9]+", options: [.regularExpression, .caseInsensitive]) {
            return "tt" + trimmed[range].dropFirst(2)  // normalize the "tt" prefix casing
        }
        return nil
    }

    // MARK: - Candidates strip

    private func candidatesStrip(_ item: ReviewMovie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 8) {
                Text("Re-pick match")
                    .font(.headline)
                Spacer()
                TextField("Override search query", text: $candidateQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .onSubmit { Task { await loadCandidates(item) } }
                Button("Search") {
                    Task { await loadCandidates(item) }
                }
                .disabled(isLoadingCandidates)
            }

            if isLoadingCandidates {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching TMDB…").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else if candidates.isEmpty {
                Text("No candidates found. Try a different search query above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(candidates) { candidate in
                            candidateCard(candidate, for: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func candidateCard(_ candidate: TmdbCandidate, for item: ReviewMovie) -> some View {
        Button {
            Task { await applyMatch(candidate, to: item) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterImage(path: candidate.posterPath, width: 120, height: 180, cornerRadius: 6)

                Text(candidate.title ?? "Untitled")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .frame(width: 120, alignment: .leading)

                HStack(spacing: 6) {
                    if let year = candidate.year {
                        Text(year).font(.caption2).foregroundColor(.secondary)
                    }
                    if let vote = candidate.voteAverage, vote > 0 {
                        Label(String(format: "%.1f", vote), systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isActing)
        .help("Set this as the pick, then Approve")
    }

    // MARK: - Reject sheet

    private var rejectSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reject movie")
                .font(.headline)

            Text(currentItem?.youtubeVideoTitle ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            TextField("Reason (e.g. not a movie, wrong content, unavailable)", text: $rejectReason)
                .textFieldStyle(.roundedBorder)
                .frame(width: 380)

            HStack {
                Spacer()
                Button("Cancel") { showRejectSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Reject", role: .destructive) {
                    if let item = currentItem {
                        showRejectSheet = false
                        Task { await reject(item) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(rejectReason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    // MARK: - Keyboard

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Don't steal keys while a modal / action is in progress, or while the
        // operator is typing in the IMDB field (so A/R/P/arrows type normally).
        guard !showRejectSheet, !isActing, !imdbFieldFocused, let item = currentItem else { return .ignored }

        switch press.key {
        case .leftArrow:
            goPrev(); return .handled
        case .rightArrow:
            goNext(); return .handled
        default:
            break
        }

        switch press.characters.lowercased() {
        case "a":
            Task { await approve(item) }; return .handled
        case "r":
            rejectReason = ""; showRejectSheet = true; return .handled
        case "p":
            pass(); return .handled
        case "j":
            goNext(); return .handled
        case "k":
            goPrev(); return .handled
        default:
            return .ignored
        }
    }

    // MARK: - Navigation

    private func goNext() {
        guard !items.isEmpty else { return }
        if currentIndex < items.count - 1 {
            currentIndex += 1
        }
        resetCandidates()
        Task { await ensureBuffer() }
    }

    private func goPrev() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        resetCandidates()
    }

    private func pass() {
        goNext()
    }

    // MARK: - Actions

    private func approve(_ item: ReviewMovie) async {
        isActing = true
        do {
            let message = try await apiService.approveReviewMovie(movieId: item.id)
            showToast(message ?? "Approved “\(item.title ?? item.youtubeVideoTitle ?? "movie")”")
            await removeCurrentAndAdvance(actedId: item.id)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isActing = false
        kbFocused = true
    }

    private func reject(_ item: ReviewMovie) async {
        let reason = rejectReason.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else { return }
        isActing = true
        do {
            let message = try await apiService.rejectReviewMovie(movieId: item.id, reason: reason)
            showToast(message ?? "Rejected")
            rejectReason = ""
            await removeCurrentAndAdvance(actedId: item.id)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isActing = false
        kbFocused = true
    }

    private func toggleCandidates(_ item: ReviewMovie) async {
        if showCandidates {
            resetCandidates()
        } else {
            showCandidates = true
            await loadCandidates(item)
        }
    }

    private func loadCandidates(_ item: ReviewMovie) async {
        isLoadingCandidates = true
        do {
            let query = candidateQuery.trimmingCharacters(in: .whitespaces)
            let data = try await apiService.getTmdbCandidates(movieId: item.id, query: query.isEmpty ? nil : query)
            candidates = data.candidates
            if candidateQuery.isEmpty, let q = data.query { candidateQuery = q }
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isLoadingCandidates = false
    }

    private func applyMatch(_ candidate: TmdbCandidate, to item: ReviewMovie) async {
        isActing = true
        do {
            let updated = try await apiService.setReviewMatch(movieId: item.id, tmdbId: candidate.tmdbId)
            // Refresh the row in place so the right pane shows the corrected pick,
            // but keep the current item's YouTube/channel-side fields — the
            // set-match response only carries the updated pick and may omit them.
            if items.indices.contains(currentIndex) {
                items[currentIndex] = item.mergingPick(from: updated)
            }
            resetCandidates()
            showToast("Match updated to “\(updated.title ?? candidate.title ?? "selection")” — review and Approve")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isActing = false
        kbFocused = true
    }

    private func applyImdb(_ item: ReviewMovie) async {
        guard let imdbId = normalizedImdbId else { return }
        isActing = true
        do {
            let updated = try await apiService.enrichReviewMovieByImdb(movieId: item.id, imdbId: imdbId)
            // Refresh the row in place so the right pane shows the corrected pick,
            // but keep the current item's YouTube/channel-side fields — the
            // enrich-manual-imdb response only carries the updated pick and may
            // omit them.
            if items.indices.contains(currentIndex) {
                items[currentIndex] = item.mergingPick(from: updated)
            }
            imdbInput = ""
            resetCandidates()
            showToast("Applied \(imdbId) → “\(updated.title ?? "match")” — review and Approve")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isActing = false
        kbFocused = true
    }

    /// Remove the acted-on item locally and keep pointing at the next one.
    private func removeCurrentAndAdvance(actedId: String) async {
        if let idx = items.firstIndex(where: { $0.id == actedId }) {
            items.remove(at: idx)
            if currentIndex > idx { currentIndex -= 1 }
        }
        total = max(0, total - 1)
        resetCandidates()

        // Need more to show? Pull the next page.
        if currentIndex >= items.count {
            await ensureBuffer(force: true)
        }
        if currentIndex >= items.count {
            currentIndex = max(0, items.count - 1)
        }
    }

    // MARK: - Data loading

    private func resetAndLoad() async {
        items = []
        currentIndex = 0
        nextPage = 1
        totalPages = 1
        total = 0
        loadError = nil
        resetCandidates()
        await loadMore()
    }

    /// Load the next page and append de-duplicated results.
    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let data = try await apiService.getReviewQueue(
                channelId: selectedChannelId.isEmpty ? nil : selectedChannelId,
                page: nextPage,
                limit: pageSize
            )
            total = data.pagination.total ?? total
            totalPages = max(data.pagination.pages ?? 1, 1)
            let existing = Set(items.map { $0.id })
            let fresh = data.movies.filter { !existing.contains($0.id) }
            items.append(contentsOf: fresh)
            nextPage += 1
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Load another page when the local buffer runs low.
    private func ensureBuffer(force: Bool = false) async {
        guard nextPage <= totalPages else { return }
        if force || currentIndex >= items.count - 2 {
            await loadMore()
        }
    }

    private func loadChannels() async {
        do {
            let data = try await apiService.getChannelsWithPatterns()
            channels = data.channels.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        } catch {
            // Channel filter is optional — review still works without it.
        }
    }

    // MARK: - Helpers

    private func resetCandidates() {
        showCandidates = false
        candidates = []
        candidateQuery = ""
        isLoadingCandidates = false
        imdbInput = ""
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 85...: return .green
        case 70..<85: return .orange
        default: return .red
        }
    }

    private func showToast(_ message: String, isError: Bool = false) {
        toastDismissTask?.cancel()
        withAnimation { toast = ToastMessage(text: message, isError: isError) }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                withAnimation { toast = nil }
            }
        }
    }
}

#Preview {
    ReviewView()
}
