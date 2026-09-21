import Foundation
import LocalAuthentication
import Network
import Security
import UserNotifications

/// Stored only as a Keychain value. Do not print, analytics-track, or copy it
/// into UserDefaults, a push payload, or a crash report.
struct KeychainSession: Codable {
    let accessToken: String
    let refreshToken: String
}

enum KeychainSessionStoreError: Error {
    case unexpectedStatus(OSStatus)
    case invalidStoredValue
}

/// A device-only, unlocked-only Keychain store for the current app session.
/// KMP's `SecureSessionStore` bridge is supplied from app composition once the
/// generated framework is linked into the Swift target.
final class KeychainSessionStore {
    private let service = "com.trippals.session"
    private let account = "current"

    func read() throws -> KeychainSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainSessionStoreError.unexpectedStatus(status) }
        guard let data = result as? Data,
              let session = try? JSONDecoder().decode(KeychainSession.self, from: data) else {
            throw KeychainSessionStoreError.invalidStoredValue
        }
        return session
    }

    func replace(_ session: KeychainSession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainSessionStoreError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// System-only local lock. Biometric information never leaves LocalAuthentication.
final class LocalAppLockAdapter {
    func unlock(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

/// Native reachability controls retry UX only; it is never server authorization.
final class NetworkReachabilityAdapter {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.trippals.network-reachability")
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

/// APNs token source. A missing token is an explicit unavailable state, never a fake value.
final class ApnsPushTokenProvider {
    private(set) var token: String?

    func update(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}

/// The app's ASAuthorizationController coordinator implements this boundary.
/// It must forward only the Apple-produced WebAuthn result to the API client.
protocol IosPasskeyCeremonyPerforming {
    func createCredential(optionsJSON: String) async throws -> String
    func getAssertion(optionsJSON: String) async throws -> String
}
