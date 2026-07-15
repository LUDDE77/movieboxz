import Foundation

/// In-app Terms of Service and Privacy Policy text. Shown as readable pop-ups
/// from Settings and on the first-launch acceptance screen, so nothing needs to
/// be hosted on the web. Keep the "Last updated" date current when either
/// document changes, and bump `LegalContent.termsVersion` if acceptance should
/// be re-collected.
enum LegalContent {

    /// Bump this when the Terms change materially and users must re-accept.
    static let termsVersion = 1

    static let lastUpdated = "July 2026"

    static let termsOfService = """
    MovieBoxZ — Terms of Service
    Last updated: \(lastUpdated)

    Welcome to MovieBoxZ. By using the app you agree to these Terms. If you do not agree, please do not use the app.

    1. What MovieBoxZ is
    MovieBoxZ is a free movie-discovery app. It helps you find and browse movies that are publicly available on YouTube. MovieBoxZ does not host, stream, upload, download, or store any video. When you choose to watch a movie, the app opens the official YouTube app (or youtube.com) to play it.

    2. Playback happens on YouTube
    All video playback takes place on YouTube and is provided by YouTube, not by MovieBoxZ. Your use of YouTube is governed by YouTube's Terms of Service (https://www.youtube.com/t/terms) and the Google Privacy Policy (https://policies.google.com/privacy). Whether a particular video is available, and in which countries it can be played, is controlled by YouTube and the content owner — not by MovieBoxZ.

    3. No account, no charge
    MovieBoxZ is free to use and does not require an account or sign-in. There are no in-app purchases or subscriptions.

    4. Content and availability
    Titles, artwork, ratings, and descriptions are provided by third-party sources (including TMDB and OMDb/IMDb) and by YouTube. MovieBoxZ makes no guarantee that any title is accurate, available, or playable in your region. A movie may be blocked by YouTube in your country; MovieBoxZ tries to hide such titles but cannot always do so.

    5. Acceptable use
    You agree to use MovieBoxZ only for lawful, personal, non-commercial purposes, and not to misuse, disrupt, or attempt to gain unauthorized access to the app or its backend.

    6. Intellectual property
    Movie and TV metadata and images are used under the terms of their providers. This product uses the TMDB API but is not endorsed or certified by TMDB. All trademarks and content belong to their respective owners. MovieBoxZ claims no ownership of any third-party content.

    7. Disclaimer of warranties
    MovieBoxZ is provided "as is" and "as available," without warranties of any kind. We do not warrant that the app will be uninterrupted, error-free, or that any specific content will be available.

    8. Limitation of liability
    To the fullest extent permitted by law, MovieBoxZ and its creators are not liable for any indirect, incidental, or consequential damages arising from your use of the app or of any third-party service it links to, including YouTube.

    9. Changes to these Terms
    We may update these Terms from time to time. Continued use of the app after an update means you accept the revised Terms.

    10. Contact
    Questions about these Terms? Contact support@movieboxz.app.
    """

    static let privacyPolicy = """
    MovieBoxZ — Privacy Policy
    Last updated: \(lastUpdated)

    MovieBoxZ is built to respect your privacy. In short: we don't require an account, and we don't collect personal data.

    1. No account, no personal data
    MovieBoxZ has no sign-in and does not ask for your name, email, or any personal information. We do not track you across apps or websites, and we use no advertising or analytics identifiers.

    2. What stays on your device
    Your favorites ("My List") and watch history are stored only on this device, in the app's local storage. They are never uploaded to us and are not linked to your identity. Deleting the app removes them.

    3. Region
    To avoid showing you movies that YouTube won't play in your country, the app sends a two-letter country code (from your device's region setting, or the region you choose in Settings) with catalog requests. This code is used only to decide which titles to show. It is not stored per user, not linked to your identity, and not used for tracking. You can change it in Settings → Region.

    4. Browsing requests
    When you browse or search, the app requests catalog information from the MovieBoxZ backend. These requests carry no account or personal identifier.

    5. Playback happens on YouTube
    When you tap to watch a movie, the app opens YouTube to play it. From that point, your activity is handled by YouTube/Google under the Google Privacy Policy (https://policies.google.com/privacy). MovieBoxZ does not receive or store your YouTube activity.

    6. Third-party data
    Movie and TV metadata and images come from TMDB and OMDb/IMDb. This product uses the TMDB API but is not endorsed or certified by TMDB.

    7. Children
    MovieBoxZ includes a Kids section of family-friendly content. We do not knowingly collect any personal information from anyone, including children.

    8. Changes to this policy
    We may update this Privacy Policy from time to time; the "Last updated" date above will change accordingly.

    9. Contact
    Questions about privacy? Contact support@movieboxz.app.
    """
}
