import SwiftUI

#if !os(tvOS)
/// Responsive grid layout helper for iOS devices
/// Provides optimized grid layouts for different iPhone and iPad sizes
struct ResponsiveGrid {

    /// Device size categories for grid optimization
    enum DeviceSize {
        case iPhoneSE        // Small phones (< 375pt width)
        case iPhoneStandard  // Standard phones (375-428pt width)
        case iPhonePlus      // Plus/Pro Max phones (> 428pt width)
        case iPad            // iPad and iPad Pro

        static var current: DeviceSize {
            let width = UIScreen.main.bounds.width

            // iPad detection
            if UIDevice.current.userInterfaceIdiom == .pad {
                return .iPad
            }

            // iPhone size detection based on width
            if width < 375 {
                return .iPhoneSE
            } else if width <= 428 {
                return .iPhoneStandard
            } else {
                return .iPhonePlus
            }
        }
    }

    /// Grid configuration for movie cards
    struct MovieGridConfig {
        let columns: [GridItem]
        let spacing: CGFloat
        let cardWidth: CGFloat
        let cardHeight: CGFloat

        static var optimized: MovieGridConfig {
            switch DeviceSize.current {
            case .iPhoneSE:
                // Small screens: 2 columns, tighter spacing
                return MovieGridConfig(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12,
                    cardWidth: 155,
                    cardHeight: 233
                )

            case .iPhoneStandard:
                // Standard screens: 2 columns, comfortable spacing
                return MovieGridConfig(
                    columns: [
                        GridItem(.flexible(), spacing: 15),
                        GridItem(.flexible(), spacing: 15)
                    ],
                    spacing: 15,
                    cardWidth: 170,
                    cardHeight: 255
                )

            case .iPhonePlus:
                // Large screens: 3 columns for more content
                return MovieGridConfig(
                    columns: [
                        GridItem(.flexible(), spacing: 15),
                        GridItem(.flexible(), spacing: 15),
                        GridItem(.flexible(), spacing: 15)
                    ],
                    spacing: 15,
                    cardWidth: 130,
                    cardHeight: 195
                )

            case .iPad:
                // iPad: Responsive columns based on orientation
                let width = UIScreen.main.bounds.width
                let columnCount = width > 1000 ? 6 : 4

                return MovieGridConfig(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columnCount),
                    spacing: 20,
                    cardWidth: 180,
                    cardHeight: 270
                )
            }
        }
    }

    /// Get adaptive columns for LazyVGrid (legacy support)
    static var adaptiveColumns: [GridItem] {
        MovieGridConfig.optimized.columns
    }

    /// Get grid spacing
    static var spacing: CGFloat {
        MovieGridConfig.optimized.spacing
    }

    /// Get horizontal padding for grid container
    static var horizontalPadding: CGFloat {
        switch DeviceSize.current {
        case .iPhoneSE:
            return 12
        case .iPhoneStandard:
            return 16
        case .iPhonePlus:
            return 20
        case .iPad:
            return 32
        }
    }
}
#endif
