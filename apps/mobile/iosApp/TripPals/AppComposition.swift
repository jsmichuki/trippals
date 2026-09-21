import Foundation

/// The SwiftUI app owns navigation and native UX. It injects Keychain,
/// AuthenticationServices, LocalAuthentication, Network and APNs adapters into
/// the KMP shared feature graph; tokens and passkey assertions are never logged.
enum AppComposition {
    static let sharedFrameworkName = "TripPalsShared"
}
