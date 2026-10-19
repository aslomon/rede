import Foundation

enum LocalModelVerification: Equatable, Sendable {
  case unverified
  case loadTested(build: String, date: String)
}

extension LlamaCppModelCatalog.Model {
  var repository: String? {
    guard downloadURL.host == "huggingface.co" else { return nil }
    let components = downloadURL.pathComponents.filter { $0 != "/" }
    guard components.count >= 4, components[2] == "resolve" else { return nil }
    return components.prefix(2).joined(separator: "/")
  }

  var minimumRuntimeBuild: String? {
    if isVerifiedInstalledGemma || LlamaCppModelCatalog.currentModels.contains(where: {
      $0.fileName == fileName && $0.sha256 == sha256 && $0.sizeBytes == sizeBytes
    }) { return "b9360" }
    return nil
  }

  /// Verification attaches to an exact artifact, never to a model family or quantization label.
  var verification: LocalModelVerification {
    isVerifiedInstalledGemma ? .loadTested(build: "b9360", date: "2026-10-19") : .unverified
  }

  private var isVerifiedInstalledGemma: Bool {
    fileName == "gemma-4-E4B-it-Q4_K_M.gguf"
      && sha256 == "90ce98129eb3e8cc57e62433d500c97c624b1e3af1fcc85dd3b55ad7e0313e9f"
      && sizeBytes == 5_335_289_824
  }
}
