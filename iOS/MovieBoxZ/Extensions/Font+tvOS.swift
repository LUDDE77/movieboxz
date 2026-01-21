import SwiftUI

// MARK: - tvOS Typography Extensions
// Optimized font sizes for 10-foot viewing distance on Apple TV

extension Font {
    #if os(tvOS)
    // tvOS-specific font sizes (10-foot UI)
    static let tvTitle1 = system(size: 76, weight: .bold)           // Featured movie titles
    static let tvTitle2 = system(size: 57, weight: .semibold)       // Section headers
    static let tvTitle3 = system(size: 48, weight: .medium)         // Card titles when focused
    static let tvHeadline = system(size: 38, weight: .semibold)     // Buttons, important text
    static let tvBody = system(size: 29, weight: .regular)          // Descriptions, body text
    static let tvCallout = system(size: 27, weight: .regular)       // Secondary text
    static let tvCaption = system(size: 25, weight: .regular)       // Tertiary text, metadata
    #else
    // iOS/iPadOS - use standard system fonts
    static let tvTitle1 = largeTitle
    static let tvTitle2 = title
    static let tvTitle3 = title2
    static let tvHeadline = headline
    static let tvBody = body
    static let tvCallout = callout
    static let tvCaption = caption
    #endif
}

// MARK: - Color Extensions for tvOS
// Semantic colors with proper contrast for TV viewing

extension Color {
    static let tvPrimary = Color.white
    static let tvSecondary = Color.white.opacity(0.7)
    static let tvTertiary = Color.white.opacity(0.5)

    #if os(tvOS)
    static let tvBackground = Color.black
    static let tvSurface = Color.white.opacity(0.1)
    #else
    static let tvBackground = Color(uiColor: .systemBackground)
    static let tvSurface = Color(uiColor: .secondarySystemBackground)
    #endif
}
