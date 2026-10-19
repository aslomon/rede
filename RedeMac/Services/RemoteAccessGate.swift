import Foundation
import os

/// Thread-safe answer to "may rede talk to OpenAI right now?".
///
/// Every production OpenAI client (rewrite, transcription, model listing, live, Decisions) is built
/// with `RemoteAccessGate.allowsRemote` as its `isRemoteAllowed` argument. The clients call it once
/// per HTTP attempt, so toggling secure-local takes effect on the very next request and never
/// relies on a Bool captured when the client was created. The gate starts closed (secure-local
/// defaults to ON) until the owner syncs it from the settings.
final class RemoteAccessGate: Sendable {
  private let secureLocal: OSAllocatedUnfairLock<Bool>

  init(secureLocalEnabled: Bool = true) {
    secureLocal = OSAllocatedUnfairLock(initialState: secureLocalEnabled)
  }

  /// Called by the settings owner whenever `secureLocalModeEnabled` changes (and once at launch).
  func update(secureLocalEnabled: Bool) {
    secureLocal.withLock { $0 = secureLocalEnabled }
  }

  var isSecureLocal: Bool { secureLocal.withLock { $0 } }

  /// The closure to inject. It re-reads the gate on every call.
  var allowsRemote: @Sendable () -> Bool {
    { [gate = self] in !gate.isSecureLocal }
  }
}
