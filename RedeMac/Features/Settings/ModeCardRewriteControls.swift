import SwiftUI

// Per-mode controls for the online rewrite model: reasoning effort and the Automatik switch.
// They render `ModelPickerModel` / `PurposeRoutingSettingsModel`; no decisions are made here.

extension ModelPickerOption {
  /// "GPT-6 Luna · Sehr schnell & günstig · empfohlen". Menu pickers show plain text only, so the
  /// badge is a quiet suffix (a second pill inside one picker would double the selection marker).
  var menuLabel: String {
    switch badge {
    case .recommended: return option.menuLabel + " · empfohlen"
    case .custom, .account, nil: return option.menuLabel
    }
  }
}

extension RewriteReasoningEffort {
  /// Short, plain labels; the higher ones say what they cost (time), not how clever they are.
  var displayName: String {
    switch self {
    case .none: return "aus"
    case .low: return "niedrig"
    case .medium: return "mittel"
    case .high: return "hoch"
    case .xhigh: return "sehr hoch"
    case .max: return "maximal"
    }
  }
}

/// "denkaufwand": shown only for models that support efforts. The stored value is written only
/// when the user picks one; until then the model default is shown and used (Luna: aus; Sol: the
/// "modellstandard" row, because nothing is sent and the API default applies).
struct RewriteEffortControl: View {
  let model: ModelPickerModel
  let onSelect: (RewriteReasoningEffort?) -> Void

  /// Row copy. `nil` is the model default, which must never read as "aus".
  static func label(for choice: RewriteReasoningEffort?) -> String {
    choice?.displayName ?? "modellstandard"
  }

  var body: some View {
    if model.showsEffortControl {
      VStack(alignment: .leading, spacing: 4) {
        Text("denkaufwand")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Picker(
          "",
          selection: Binding(get: { model.effectiveEffort }, set: { onSelect($0) })
        ) {
          ForEach(model.effortChoices, id: \.self) { choice in
            Text(Self.label(for: choice)).tag(choice)
          }
        }
        .labelsHidden()
        .controlSize(.small)

        if model.effectiveEffortIsSlow {
          Text("denkt länger nach. dein text kommt später.")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

/// Per-mode Automatik switch. Visible for rewriting modes only; disabled (with the reason)
/// whenever the global switch is off, secure-local is on, or the rewrite runs locally.
struct AutomatikModeToggle: View {
  let routing: PurposeRoutingSettingsModel
  let config: ModeConfig
  let rewriteBackend: RewriteBackend
  let onChange: (PurposeRoutingMode) -> Void

  var body: some View {
    if routing.offersMode(config) {
      VStack(alignment: .leading, spacing: 4) {
        Toggle(
          isOn: Binding(
            get: { config.rewrite.purposeRouting.isAutomatic },
            set: { onChange($0 ? .automatic : .off) })
        ) {
          Label("zweck automatisch erkennen", systemImage: "wand.and.stars.inverse")
            .labelStyle(QuietToggleLabelStyle())
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!routing.modeToggleEnabled(config, rewriteBackend: rewriteBackend))

        if let reason = disabledReason {
          Text(reason)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  /// Why the switch cannot be used right now; nil when it is usable.
  private var disabledReason: String? {
    if let block = routing.block, block == .secureLocal { return block.copy }
    if rewriteBackend != .openai { return "automatik braucht das online-modell." }
    if !routing.isEnabled { return "erst unter modelle → online-extras einschalten." }
    return routing.block?.copy
  }
}

extension NetworkFeatureBlock {
  /// One factual sentence, no scolding.
  var copy: String {
    switch self {
    case .secureLocal: return "im lokalmodus aus: nichts verlässt deinen Mac."
    case .localRewrite: return "braucht das online-modell."
    case .noAPIKey: return "braucht deinen OpenAI-key."
    case .noMicrophone: return "braucht zugriff aufs mikrofon."
    }
  }
}
