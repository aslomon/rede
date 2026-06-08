import SwiftUI

/// Inline status for the local rewrite model.
///
/// Selection and downloads live in the standalone "Lokale Modelle" window so there is only one
/// place where the active model can be chosen. This view only reports the current state and opens
/// that window.
struct LocalLLMModelPicker: View {
  @Bindable var appState: AppState

  private var manager: LocalModelManager { appState.localModelManager }

  private var selection: LocalLLMSelection {
    appState.appSettings.selectedLocalLLM
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text("Lokales Sprachmodell")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer()
        statusPill
      }

      Text(statusLine)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      manageButton
    }
    .task {
      await manager.refresh()
    }
  }

  @ViewBuilder
  private var statusPill: some View {
    if selection.runtime == .llamaCpp {
      if selectedLlamaCppModel != nil {
        BlitzStatusPill(state: .ready, label: "Gewählt")
      } else if manager.llamaCppInstalled.isEmpty {
        BlitzStatusPill(state: .download, label: "Laden")
      } else {
        BlitzStatusPill(state: .warning, label: "Auswählen")
      }
    } else if !manager.serverReachable {
      BlitzStatusPill(state: .warning, label: manager.ollamaAppInstalled ? "Starten" : "Setup")
    } else if selectedInstalledRecord != nil {
      BlitzStatusPill(state: .ready, label: "Gewählt")
    } else if manager.installed.isEmpty {
      BlitzStatusPill(state: .download, label: "Laden")
    } else {
      BlitzStatusPill(state: .warning, label: "Auswählen")
    }
  }

  private var statusLine: String {
    if selection.runtime == .llamaCpp {
      if let selectedLlamaCppModel {
        return "Aktiv: \(selectedLlamaCppModel.displayName)"
      }
      if manager.llamaCppInstalled.isEmpty {
        return "Noch kein GGUF-Modell für llama.cpp installiert."
      }
      return "\(manager.llamaCppInstalled.count) GGUF-Modell(e) installiert. Wähle das aktive Modell in der Modellseite."
    }
    if !manager.serverReachable {
      return manager.ollamaAppInstalled
        ? "Ollama ist installiert, läuft aber noch nicht. Öffne die Modellseite zum Starten."
        : "Ollama ist noch nicht installiert. Öffne die Modellseite für die geführte Installation."
    }
    if let selectedInstalledRecord {
      return "Aktiv: \(selectedInstalledRecord.name)"
    }
    if manager.installed.isEmpty {
      return "Noch kein lokales Umschreibmodell geladen."
    }
    return "\(manager.installed.count) Modell(e) geladen. Wähle das aktive Modell in der Modellseite."
  }

  private var selectedInstalledRecord: OllamaService.InstalledModel? {
    guard selection.runtime == .ollama, selection.isConfigured else { return nil }
    return manager.installed.first { OllamaService.isInstalled(selection.modelID, in: [$0.name]) }
  }

  private var selectedLlamaCppModel: LlamaCppModelCatalog.Model? {
    guard selection.runtime == .llamaCpp, selection.isConfigured else { return nil }
    return manager.installedLlamaCppModel(for: selection.modelID)
  }

  // MARK: - Actions

  private var manageButton: some View {
    HStack(spacing: 8) {
      Button {
        NotificationCenter.default.post(name: .openLocalModelsWindow, object: nil)
      } label: {
        Label(
          manageButtonTitle,
          systemImage: "square.and.arrow.down.on.square"
        )
        .font(.system(size: 10.5, weight: .medium))
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))

      Button("Prüfen") {
        Task { await manager.refresh() }
      }
      .font(.system(size: 10, weight: .medium))
      .buttonStyle(PopoverActionButtonStyle(.quiet))
      .disabled(manager.isRefreshing)
    }
  }

  private var manageButtonTitle: String {
    if !manager.serverReachable { return "Modelle einrichten …" }
    return manager.installed.isEmpty ? "Modelle laden …" : "Modelle verwalten …"
  }
}
