import SwiftUI
import SafariServices

struct VideoPlayerView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SafariPlayerView(url: movie.youtubeURL ?? URL(string: "https://youtube.com")!)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
    }
}

// MARK: - SafariPlayerView

struct SafariPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .red
        vc.preferredBarTintColor = .black
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
