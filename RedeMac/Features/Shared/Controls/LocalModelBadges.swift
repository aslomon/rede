import Foundation

enum LocalModelBadge: Hashable {
  /// Added to the catalog in the current refresh.
  case new
  /// Never load-tested on a Mac by rede yet: it may download fine and still behave oddly.
  case notLocallyVerified
  /// This exact artifact loaded and ran with the recorded llama.cpp build. Not a quality rating.
  case locallyVerified(build: String, date: String)
}

/// Badges for open-weight models. Pure; reads the catalog's own per-artifact `verification`.
///
/// "neu" marks the entries added by the current refresh (`LlamaCppModelCatalog.currentModels`).
/// Verification attaches to the exact artifact (file name, checksum, size), so a quantization
/// sibling of a verified model never inherits it, and an installed copy of the verified file
/// carries it even though it is not a catalog row. Legacy rows carry no badge: nothing new is
/// claimed about them.
enum LocalModelBadges {
  static func badges(for model: LlamaCppModelCatalog.Model) -> [LocalModelBadge] {
    let isCurrent = LlamaCppModelCatalog.currentModels.contains { $0.id == model.id }
    var badges: [LocalModelBadge] = isCurrent ? [.new] : []
    switch model.verification {
    case .loadTested(let build, let date): badges.append(.locallyVerified(build: build, date: date))
    case .unverified: if isCurrent { badges.append(.notLocallyVerified) }
    }
    return badges
  }
}
