import SwiftUI

/// "neu" / "nicht lokal geprüft" / "lokal geprüft" from the model's own metadata. Informational
/// only: nothing downloads until the explicit "laden" button of that row is pressed.
struct LocalModelBadgeRow: View {
  let model: LlamaCppModelCatalog.Model

  var body: some View {
    ForEach(LocalModelBadges.badges(for: model), id: \.self) { badge in
      switch badge {
      case .new:
        RedeStatusPill(state: .download, label: "neu")
      case .notLocallyVerified:
        RedeStatusPill(state: .muted, label: "nicht lokal geprüft")
      case .locallyVerified(let build, let date):
        RedeStatusPill(state: .ready, label: "lokal geprüft")
          .help("geladen und gelaufen mit llama.cpp \(build) (\(date)). kein qualitätsurteil.")
      }
    }
  }
}
