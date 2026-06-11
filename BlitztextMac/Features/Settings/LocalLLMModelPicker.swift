import SwiftUI

/// Inline status AND selection for the local rewrite model: every installed GGUF model shows as a
/// selectable `ModelSelectRow` right here — no window round-trip just to activate a model that is
/// already on disk. Downloads and deletes stay in the standalone "lokale modelle" window.
/// llama.cpp is the only local runtime.
struct LocalLLMModelPicker: View {
  @Bindable var appState: AppState
  /// The compact "aktives modell" header row with the status pill. Off in the Modelle tab, where
  /// the surrounding `SettingsSection` header carries the pill instead.
  var showsStatusHeader: Bool = true

  private var manager: LocalModelManager { appState.localModelManager }

  private var selection: LocalLLMSelection {
    appState.appSettings.selectedLocalLLM
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if showsStatusHeader {
        HStack(spacing: 6) {
          Text("aktives modell")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
          Spacer()
          statusPill
        }
      }

      if manager.llamaCppInstalled.isEmpty {
        Text("noch kein GGUF-Modell auf diesem Mac — lade eins über „modelle laden …\u{201C}.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        // Installed models are directly selectable here (downloaded ⇒ one tap from active).
        ForEach(manager.llamaCppInstalled) { model in
          ModelSelectRow(
            title: model.displayName,
            subtitle: [model.parameterSize, model.quantization].joined(separator: " · "),
            isActive: isActive(model),
            select: { selectModel(model) }
          )
        }
      }

      manageRow
    }
    .task {
      await manager.refresh()
      // Downloaded models should be usable without a manual pick.
      appState.adoptInstalledLocalModelsIfNeeded()
    }
  }

  @ViewBuilder
  private var statusPill: some View {
    if selectedLlamaCppModel != nil {
      BlitzStatusPill(state: .ready, label: "gewählt")
    } else if manager.llamaCppInstalled.isEmpty {
      BlitzStatusPill(state: .download, label: "laden")
    } else {
      BlitzStatusPill(state: .warning, label: "auswählen")
    }
  }

  private var selectedLlamaCppModel: LlamaCppModelCatalog.Model? {
    guard selection.isConfigured else { return nil }
    return manager.installedLlamaCppModel(for: selection.modelID)
  }

  private func isActive(_ model: LlamaCppModelCatalog.Model) -> Bool {
    selection == LocalLLMSelection(runtime: .llamaCpp, modelID: model.id)
  }

  private func selectModel(_ model: LlamaCppModelCatalog.Model) {
    appState.appSettings.selectedLocalLLM = LocalLLMSelection(
      runtime: .llamaCpp, modelID: model.id)
  }

  // MARK: - Actions

  private var manageRow: some View {
    HStack(spacing: 8) {
      Button {
        NotificationCenter.default.post(name: .openLocalModelsWindow, object: nil)
      } label: {
        Label(manageButtonTitle, systemImage: "macwindow")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))

      Button {
        Task { await manager.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(PopoverIconButtonStyle(.quiet))
      .disabled(manager.isRefreshing)
      .help("status prüfen")
    }
  }

  private var manageButtonTitle: String {
    manager.llamaCppInstalled.isEmpty ? "modelle laden …" : "modelle verwalten …"
  }
}
