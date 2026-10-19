import Foundation

/// Content-free transport policy failure. The composition root supplies the current policy.
enum OpenAIRemotePolicyError: LocalizedError, Equatable, Sendable {
  case remoteNotAllowed

  var errorDescription: String? {
    "Online-Verarbeitung ist im sicheren lokalen Modus gesperrt."
  }
}
