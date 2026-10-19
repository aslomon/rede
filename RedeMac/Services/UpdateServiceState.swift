import Foundation

extension UpdateService {
  enum Failure: Equatable, Sendable {
    case network, invalidSignature, cannotInstall, other
  }

  enum Status: Equatable, Sendable {
    case idle(lastChecked: Date?)
    case checking
    case downloading(fraction: Double?)
    case available(version: String)
    case staged(version: String)
    case failed(Failure)
  }
}
