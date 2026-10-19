import Foundation

/// Live and Decisions share one bounded native worker; cancellation never joins a synchronous lookup.
enum LiveCredentialLoader {
    static func load(_ loader: @escaping @Sendable () -> String?,
                     isRemoteAllowed: @escaping @Sendable () -> Bool = { true }) async throws -> String? {
        do {
            return try await DecisionsCredentialLoader.shared.load(loader, isRemoteAllowed: isRemoteAllowed)
        } catch is RemoteRequestBlocked {
            throw LiveFailure.remoteNotAllowed
        } catch DecisionsClientError.timedOut {
            throw LiveFailure.timeout
        }
    }
}
