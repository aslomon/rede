import SwiftUI

/// An icon-only "trash" button that confirms before deleting an installed model (which frees disk
/// space). Shared across model types — Whisper and GGUF rows — so the destructive flow + copy
/// stays consistent everywhere.
struct DeleteModelButton: View {
  /// Label shown in the confirmation title (e.g. "Gemma 3 · 12B" or "Whisper Large v3").
  let displayName: String
  /// Already-formatted freed size for the confirmation message (e.g. "2,1 GB" or "598 MB").
  let freedSizeText: String?
  /// The destructive action to run when the user confirms.
  let onDelete: () -> Void

  @State private var confirming = false

  init(displayName: String, freedSizeText: String?, onDelete: @escaping () -> Void) {
    self.displayName = displayName
    self.freedSizeText = freedSizeText
    self.onDelete = onDelete
  }

  var body: some View {
    // spec #13: icon-only trash button (PopoverIconButtonStyle(.danger), 28×28 touch target)
    // spec #13: .accessibilityLabel includes model display name for VoiceOver context
    Button {
      confirming = true
    } label: {
      Image(systemName: "trash")
    }
    .buttonStyle(PopoverIconButtonStyle(.danger))
    .accessibilityLabel("\(displayName) entfernen")
    .confirmationDialog(
      "\(displayName) entfernen?",
      isPresented: $confirming,
      titleVisibility: .visible
    ) {
      Button("entfernen", role: .destructive) { onDelete() }
      Button("abbrechen", role: .cancel) {}
    } message: {
      if let freedSizeText {
        Text(
          "gibt \(freedSizeText) auf der disk frei. "
            + "du kannst das modell später jederzeit neu laden.")
      } else {
        Text("du kannst das modell später jederzeit neu laden.")
      }
    }
  }
}
