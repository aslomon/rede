import SwiftUI

/// One quiet line under a finished rewrite saying what Automatik did. It never claims a perfect
/// result: when the detection was unsure the text says everything ran as usual.
struct PurposeRoutingNoteView: View {
  let note: PurposeRoutingNote

  var body: some View {
    Label(note.copy, systemImage: note.symbolName)
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 8)
      .accessibilityElement(children: .combine)
  }
}

extension PurposeRoutingNote {
  var copy: String {
    switch self {
    case .detected(.email): return "als e-mail erkannt — umschreiben angepasst."
    case .detected(.aiPrompt): return "als ki-prompt erkannt — umschreiben angepasst."
    case .detected(.other), .noSpecialPurpose:
      return "kein besonderer zweck erkannt — wie gewohnt umgeschrieben."
    case .fellBack(.tooShort): return "zu kurz für automatik — wie gewohnt umgeschrieben."
    case .fellBack: return "automatik war unsicher — wie gewohnt umgeschrieben."
    }
  }

  var symbolName: String {
    switch self {
    case .detected(.email): return "envelope"
    case .detected(.aiPrompt): return "wand.and.stars.inverse"
    default: return "equal.circle"
    }
  }
}
