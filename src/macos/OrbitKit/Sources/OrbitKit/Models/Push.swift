import Foundation

/// A device's APNs token registration (`POST /api/push/register`). The server stores it against the
/// authenticated user and pushes "needs your reply" notifications to it. `environment` tells the
/// server which APNs host to use for this token — `production` for App Store / TestFlight builds,
/// `sandbox` for development builds — so one server can serve both without guessing.
public struct DeviceTokenRequest: Codable, Equatable, Sendable {
    public let token: String        // hex-encoded APNs device token
    public let platform: String     // "ios"
    public let environment: String  // "production" | "sandbox"
    public let bundleId: String     // e.g. io.orbitd.app

    public init(token: String, platform: String = "ios", environment: String, bundleId: String) {
        self.token = token
        self.platform = platform
        self.environment = environment
        self.bundleId = bundleId
    }
}
