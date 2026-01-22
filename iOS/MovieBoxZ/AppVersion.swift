import Foundation

/// App Version Tracking
/// INCREMENT THIS NUMBER EVERY TIME YOU UPDATE THE PROJECT
struct AppVersion {
    static let current = "1.0.0"
    static let build = 16

    static var fullVersion: String {
        "\(current) (Build \(build))"
    }
}
