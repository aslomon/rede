import SwiftUI

/// System tab → "updates". Wires the real service into the pure `UpdatesSettingsContent`.
struct UpdatesSettingsSection: View {
  let appState: AppState
  @State private var model: UpdateSettingsModel

  init(appState: AppState) {
    self.appState = appState
    _model = State(
      initialValue: UpdateSettingsModel(
        service: appState.updateService,
        isBusy: { appState.updateService.isBusy() }))
  }

  var body: some View {
    UpdatesSettingsContent(
      model: model, versionText: appState.updateService.appVersionText,
      lastCheckText: appState.updateService.lastCheckDisplayText)
  }
}

/// Status first, then the primary action, then the two switches. Logic lives in
/// `UpdateSettingsModel`; this view only renders it and holds the German copy.
struct UpdatesSettingsContent: View {
  let model: UpdateSettingsModel
  let versionText: String
  let lastCheckText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        SectionLabel(text: "updates", icon: "arrow.triangle.2.circlepath")
        RedeStatusPill(state: model.statusLine.pillState, label: model.statusLine.pillLabel)
        Spacer()
      }

      HStack(spacing: 8) {
        Text(versionText)
          .font(.system(size: 11.5, weight: .semibold))
        if case .available(let version) = model.statusLine {
          Text("→ \(version)")
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
        }
      }

      if let detail = statusDetail {
        Text(detail)
          .font(.system(size: 10.5))
          .foregroundStyle(model.statusLine.isFailure ? Color.orange : Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text(lastCheckText)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }

      actions
      switches

      // Compact data-flow note (DESIGN.md: sensible Hinweise als sichtbare Caption).
      Text(
        "beim prüfen gehen nur app- und macOS-version an github — keine weiteren daten, "
          + "kein geräteprofil. das gilt auch im sicheren lokalmodus: updates sind keine "
          + "übertragung deiner inhalte."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var statusDetail: String? {
    model.statusLine.detail(
      waitsForDictation: model.installWaitsForDictation,
      installNotStarted: model.installNotStarted)
  }

  // MARK: - Actions

  private var actions: some View {
    HStack(spacing: 8) {
      Button {
        model.checkNow()
      } label: {
        Label("jetzt nach updates suchen", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
      .disabled(!model.canCheckNow)

      if model.offersInstall {
        Button {
          model.installNow()
        } label: {
          Label("jetzt installieren", systemImage: "arrow.down.app")
        }
        .buttonStyle(PopoverActionButtonStyle(.primary))
        .disabled(!model.canInstallNow)
        .help(model.installHelp)
      }
    }
  }

  // MARK: - Switches

  private var switches: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle(isOn: Binding(get: { model.automaticChecks }, set: { model.automaticChecks = $0 })) {
        Label("automatisch täglich prüfen", systemImage: "calendar")
          .labelStyle(QuietToggleLabelStyle())
      }
      .toggleStyle(.switch)
      .controlSize(.small)

      Toggle(
        isOn: Binding(get: { model.automaticDownloads }, set: { model.automaticDownloads = $0 })
      ) {
        Label("updates automatisch laden, beim beenden installieren", systemImage: "arrow.down.app")
          .labelStyle(QuietToggleLabelStyle())
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .disabled(!model.canChangeDownloads)

      if !model.canChangeDownloads {
        Text("gilt nur, solange die tägliche prüfung an ist.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Copy

extension UpdateStatusLine {
  var pillState: RedeStatusPill.State {
    switch self {
    case .unavailable, .checking: return .muted
    case .idle(let lastChecked): return lastChecked == nil ? .muted : .ready
    case .downloading, .available: return .download
    case .staged: return .ready
    case .failed: return .warning
    }
  }

  var pillLabel: String {
    switch self {
    case .unavailable: return "nicht verfügbar"
    case .idle(let lastChecked): return lastChecked == nil ? "noch nicht geprüft" : "aktuell"
    case .checking: return "prüfe …"
    case .downloading(let fraction):
      guard let fraction else { return "lädt …" }
      return "lädt \(Int((fraction * 100).rounded())) %"
    case .available(let version): return "update \(version)"
    case .staged(let version): return "\(version) bereit"
    case .failed: return "fehlgeschlagen"
    }
  }

  var isFailure: Bool {
    if case .failed = self { return true }
    return false
  }

  /// One calm sentence under the status, or nil to show the last-check line instead.
  /// `installNotStarted`: the service refused "jetzt installieren". Say so, promise no restart.
  func detail(waitsForDictation: Bool, installNotStarted: Bool = false) -> String? {
    switch self {
    case .available:
      return "ein update wartet auf dich. mit „jetzt nach updates suchen“ startest du es."
    case .staged:
      if installNotStarted { return "starten ging gerade nicht. das update bleibt bereit." }
      return waitsForDictation
        ? "wartet, bis dein diktat fertig ist."
        : "wird beim beenden von rede installiert."
    case .failed(let failure):
      return failure.message
    default:
      return nil
    }
  }
}

extension UpdateService.Failure {
  var message: String {
    switch self {
    case .network: return "update konnte nicht geladen werden. prüf deine verbindung."
    case .invalidSignature:
      return "update abgelehnt: die signatur stimmt nicht. nichts wurde installiert."
    case .cannotInstall:
      return "update konnte nicht installiert werden. rede läuft unverändert weiter."
    case .other: return "update fehlgeschlagen. versuch es später nochmal."
    }
  }
}
