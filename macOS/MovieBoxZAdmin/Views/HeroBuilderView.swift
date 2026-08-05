import SwiftUI

// MARK: - Hero Builder
// Curate the image shown for each featured movie in the app's hero carousel.
// Pick from TMDB alternates, the movie's current backdrop/poster, or the
// YouTube thumbnail. When no image is chosen the app falls back automatically
// (backdrop -> blurred poster).

struct HeroBuilderView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var featured: [FeaturedMovieItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editing: FeaturedMovieItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if isLoading && featured.isEmpty {
                Spacer()
                ProgressView("Loading featured movies…")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if let errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40)).foregroundColor(.orange)
                    Text(errorMessage).multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if featured.isEmpty {
                Spacer()
                Text("No featured movies yet. Add some in the Featured section.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(featured) { movie in
                            movieRow(movie)
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { movie in
            HeroImagePickerSheet(movie: movie, apiService: apiService) {
                await load()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hero Builder").font(.largeTitle).bold()
                Text("Pick the image shown for each featured movie in the app's hero carousel.")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding()
    }

    private func movieRow(_ movie: FeaturedMovieItem) -> some View {
        HStack(spacing: 16) {
            // Current hero preview (16:9)
            heroThumb(movie.currentHeroURL)
                .frame(width: 220, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title).font(.headline)
                HStack(spacing: 6) {
                    Text("#\(movie.featuredOrder)")
                        .font(.caption).foregroundColor(.secondary)
                    if movie.hasCustomHero {
                        Label("Custom hero", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundColor(.green)
                    } else {
                        Label("Auto", systemImage: "wand.and.stars")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Text(movie.hasCustomHero
                     ? "Showing an admin-picked image."
                     : "Auto: using the backdrop, or a blurred poster if none.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Button {
                editing = movie
            } label: {
                Label("Choose image…", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func heroThumb(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                ZStack { Color.gray.opacity(0.15); ProgressView() }
            default:
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "photo").foregroundColor(.secondary)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            featured = try await apiService.getFeaturedMovies()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Image picker sheet

private struct HeroImagePickerSheet: View {
    let movie: FeaturedMovieItem
    let apiService: AdminAPIService
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var data: HeroCandidatesData?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose hero image").font(.title2).bold()
                    Text(movie.title).foregroundColor(.secondary)
                }
                Spacer()
                if isSaving { ProgressView().scaleEffect(0.7) }
                Button("Reset to automatic") {
                    Task { await save(nil) }
                }
                .disabled(isSaving || !(data?.current != nil))
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading images from TMDB & other channels…").frame(maxWidth: .infinity)
                Spacer()
            } else if let errorMessage {
                Spacer()
                Text(errorMessage).foregroundColor(.red).frame(maxWidth: .infinity)
                Spacer()
            } else if let data {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        section("From other channels", data.candidates.filter { $0.source == "channel" })
                        section("Backdrops (recommended)", data.candidates.filter { $0.source != "channel" && $0.isLandscape })
                        section("Posters", data.candidates.filter { $0.source != "channel" && !$0.isLandscape })
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .task { await loadCandidates() }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [HeroCandidate]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(items) { candidate in
                        candidateCell(candidate)
                    }
                }
            }
        }
    }

    private func candidateCell(_ candidate: HeroCandidate) -> some View {
        let isSelected = candidate.url == data?.current
        return Button {
            Task { await save(candidate.url) }
        } label: {
            VStack(spacing: 6) {
                AsyncImage(url: candidate.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        ZStack { Color.gray.opacity(0.15); ProgressView() }
                    default:
                        ZStack { Color.gray.opacity(0.15); Image(systemName: "photo").foregroundColor(.secondary) }
                    }
                }
                .aspectRatio(candidate.isLandscape ? 16.0/9.0 : 2.0/3.0, contentMode: .fill)
                .frame(height: candidate.isLandscape ? 150 : 240)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                lineWidth: isSelected ? 4 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2).foregroundColor(.accentColor)
                            .background(Circle().fill(.white))
                            .padding(6)
                    }
                }

                Text(sourceLabel(candidate))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func sourceLabel(_ c: HeroCandidate) -> String {
        if let ch = c.channel, !ch.isEmpty {
            return "\(ch) · \(c.type)"
        }
        switch c.source {
        case "tmdb": return "TMDB \(c.type)"
        case "current": return "Current \(c.type)"
        case "youtube": return "YouTube thumbnail"
        default: return c.type
        }
    }

    private func loadCandidates() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await apiService.getHeroCandidates(movieId: movie.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ url: String?) async {
        isSaving = true
        do {
            try await apiService.setHeroImage(movieId: movie.id, url: url)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
