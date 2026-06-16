import SwiftUI

/// Inline selection for the local rewrite model: every installed GGUF model shows as a selectable
/// `ModelSelectRow` right here — no window round-trip just to activate a model that is already on
/// disk. Downloads and deletes stay in the standalone "lokale modelle" window. llama.cpp is the
/// only local runtime.
struct LocalLLMModelPicker: View {
  @Bindable var appState: AppState

  private var manager: LocalModelManager { appState.localModelManager }

  private var selection: LocalLLMSelection {
    appState.appSettings.selectedLocalLLM
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
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
