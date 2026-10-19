import Foundation

/// One process-wide native lookup at a time. Cancelled callers never await uninterruptible Keychain work.
final class DecisionsCredentialLoader: @unchecked Sendable {
    static let shared = DecisionsCredentialLoader()
    private let queue = DispatchQueue(label: "app.rede.decisions-credential", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false

    func load(_ provider: @escaping @Sendable () -> String?,
              isRemoteAllowed: @escaping @Sendable () -> Bool) async throws -> String? {
        try Task.checkCancellation()
        let waiter = CredentialWaiter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard waiter.install(continuation) else { return }
                guard reserve() else {
                    waiter.complete(.failure(DecisionsClientError.timedOut))
                    return
                }
                queue.async { [self] in
                    let result = Result {
                        guard waiter.isPending else { throw CancellationError() }
                        guard isRemoteAllowed() else { throw RemoteRequestBlocked() }
                        let key = provider()
                        guard waiter.isPending else { throw CancellationError() }
                        guard isRemoteAllowed() else { throw RemoteRequestBlocked() }
                        return key
                    }
                    lock.withLock { busy = false }
                    waiter.complete(result)
                }
            }
        } onCancel: { waiter.complete(.failure(CancellationError())) }
    }

    private func reserve() -> Bool {
        lock.withLock {
            guard !busy else { return false }
            busy = true
            return true
        }
    }
}

private final class CredentialWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Error>?
    private var completed = false
    var isPending: Bool { lock.withLock { !completed } }

    func install(_ continuation: CheckedContinuation<String?, Error>) -> Bool {
        let installed = lock.withLock {
            guard !completed else { return false }
            self.continuation = continuation
            return true
        }
        if !installed { continuation.resume(throwing: CancellationError()) }
        return installed
    }

    func complete(_ result: Result<String?, Error>) {
        let waiting = lock.withLock { () -> CheckedContinuation<String?, Error>? in
            guard !completed else { return nil }
            completed = true
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(with: result)
    }
}
