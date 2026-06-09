import AppKit
import SwiftUI

/// The "Lokale Modelle" management page: this Mac's capabilities, the llama.cpp GGUF rewrite
/// models, and the llama.cpp embedding model that powers semantic e-mail memory. Hosted in its own
/// window by `LocalModelsWindowController`. Everything runs through the bundled llama.cpp helper —
/// no Ollama, nothing leaves the Mac.
struct LocalModelsView: View {
  @Bindable var appState: AppState
  @Bindable var manager: LocalModelManager
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        // Hardware facts first — the per-model RAM fit is based on them.
        VStack(alignment: .leading, spacing: 8) {
          SectionLabel(text: "Dieser Mac")
          systemCard
        }

        // Engine 1 — Transcription (Whisper). Always local.
        WhisperModelsSection(appState: appState)

        Divider().opacity(0.4)

        // Engine 2 — Rewrite. llama.cpp (GGUF) is the only local runtime.
        llamaCppSection

        Divider().opacity(0.4)

        // Engine 3 — Embedding (llama.cpp). Powers semantic e-mail memory.
        embeddingSection

        if let error = manager.lastError { errorBanner(error) }

        footerHint
      }
      // Top inset clears the floating traffic lights (full-size-content title bar).
      .padding(.horizontal, 16)
      .padding(.top, 38)
      .padding(.bottom, 16)
    }
    .frame(minWidth: 540, minHeight: 580)
    .task { await manager.refresh() }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          BrandMark(size: 18)
          Text("Lokale Modelle")
            .font(.system(size: 16, weight: .semibold))
        }
        Text("Transkription, Sprachmodell und Embedding — laden, neu laden, entfernen.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        Task { await manager.refresh() }
      } label: {
        Label("Aktualisieren", systemImage: "arrow.clockwise")
          .font(.system(size: 11, weight: .medium))
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
      .disabled(manager.isRefreshing)
    }
  }

  // MARK: - System card

  private var systemCard: some View {
    HStack(spacing: 18) {
      systemStat("cpu", "Chip", manager.system.chipName)
      systemStat("memorychip", "Arbeitsspeicher", manager.system.formattedRAM)
      systemStat("internaldrive", "Frei auf Disk", manager.system.formattedFreeDisk)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassCard(cornerRadius: 10)
  }

  private func systemStat(_ symbol: String, _ caption: String, _ value: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(caption).font(.system(size: 9.5)).foregroundStyle(.secondary)
        Text(value).font(.system(size: 12, weight: .semibold))
      }
    }
  }

  // MARK: - llama.cpp rewrite models

  private var llamaCppSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(text: "Sprachmodell · Umschreiben")

      if manager.llamaCppInstalled.isEmpty {
        Text("GGUF-Modelle laufen direkt über den gebündelten lokalen llama.cpp-Helper.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
        if let recommended = manager.recommended {
          recommendationCard(recommended)
        }
      } else {
        // What you downloaded + which one is active.
        ForEach(manager.llamaCppInstalled) { model in
          installedModelRow(model)
        }
      }

      // The full catalog stays collapsed so the page isn't a permanent wall of models.
      InfoDisclosure(catalogDisclosureTitle) {
        VStack(alignment: .leading, spacing: 10) {
          if !manager.llamaCppInstalled.isEmpty, let recommended = manager.recommended,
            !manager.isLlamaCppInstalled(recommended.id)
          {
            recommendationCard(recommended)
          }
          ForEach(notInstalledChatModels) { model in
            llamaCppCatalogRow(model)
          }
        }
      }
    }
  }

  private var catalogDisclosureTitle: String {
    manager.llamaCppInstalled.isEmpty ? "Alle Modelle anzeigen" : "Weitere Modelle laden"
  }

  private var notInstalledChatModels: [LlamaCppModelCatalog.Model] {
    LlamaCppModelCatalog.models.filter { !manager.isLlamaCppInstalled($0.id) }
  }

  /// One downloaded model: shows what is installed and lets you activate / deactivate / delete it.
  private func installedModelRow(_ model: LlamaCppModelCatalog.Model) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 13))
        .foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 1) {
        Text(model.displayName)
          .font(.system(size: 12, weight: .semibold))
        Text([model.parameterSize, model.quantization].joined(separator: " · "))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isActive(llamaCppModel: model) {
        BlitzStatusPill(state: .ready, label: "Aktiv")
        Button {
          appState.appSettings.selectedLocalLLM = LocalLLMSelection()
        } label: {
          Text("Deaktivieren").font(.system(size: 10.5, weight: .medium))
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))
      } else {
        Button {
          selectLlamaCpp(model)
        } label: {
          Label("Aktivieren", systemImage: "checkmark.circle")
        }
        .buttonStyle(PopoverActionButtonStyle(.primary))
      }
      Text(SystemCapabilities.formatGB(model.downloadGB))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      Button {
        if isActive(llamaCppModel: model) {
          appState.appSettings.selectedLocalLLM = LocalLLMSelection()
        }
        manager.deleteLlamaCpp(model)
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(PopoverActionButtonStyle(.danger))
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8).fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
    )
  }

  private func llamaCppCatalogRow(_ model: LlamaCppModelCatalog.Model) -> some View {
    let installed = manager.isLlamaCppInstalled(model.id)
    let downloading = manager.isDownloadingLlamaCpp(model.id)
    let state = manager.llamaCppDownloads[model.id]
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: installed ? "checkmark.circle.fill" : "arrow.down.circle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(installed ? .green : .blue)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(model.displayName)
              .font(.system(size: 12.5, weight: .semibold))
            if isRecommended(model) {
              Text("Empfohlen")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.blue.opacity(0.15)))
                .foregroundStyle(.blue)
            }
          }
          Text(model.blurb)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Text(
            "\(model.parameterSize) · \(model.quantization) · \(SystemCapabilities.formatGB(model.downloadGB)) · \(model.licenseName)"
          )
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
        }
        Spacer()
        if installed {
          if isActive(llamaCppModel: model) {
            BlitzStatusPill(state: .ready, label: "Aktiv")
          } else {
            Button {
              selectLlamaCpp(model)
            } label: {
              Label("Nutzen", systemImage: "checkmark.circle")
            }
            .buttonStyle(PopoverActionButtonStyle(.primary))
          }
        } else if downloading {
          Button {
            manager.cancelLlamaCppDownload(model.id)
          } label: {
            Label("Stopp", systemImage: "xmark.circle")
          }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
        } else {
          Button {
            manager.downloadLlamaCpp(model)
          } label: {
            Label("Laden", systemImage: "arrow.down.circle.fill")
          }
          .buttonStyle(PopoverActionButtonStyle(.primary))
          .disabled(!manager.system.diskFits(downloadGB: model.downloadGB))
        }
      }
      if let state {
        HStack(spacing: 8) {
          ProgressView(value: state.fraction)
            .controlSize(.small)
          Text(state.statusText)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8).fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
    )
  }

  // MARK: - Recommendation

  private func isRecommended(_ model: LlamaCppModelCatalog.Model) -> Bool {
    manager.recommended?.id == model.id
  }

  private func recommendationCard(_ model: LlamaCppModelCatalog.Model) -> some View {
    let downloading = manager.isDownloadingLlamaCpp(model.id)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
        Text("Empfohlen für deinen Mac").font(.system(size: 11, weight: .semibold))
      }
      .foregroundStyle(.blue)

      Text(model.displayName).font(.system(size: 14, weight: .semibold))
      Text(manager.system.recommendationReason(for: model))
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Text("\(SystemCapabilities.formatGB(model.downloadGB)) Download")
          .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        Spacer(minLength: 8)
        if downloading {
          Label("Lädt …", systemImage: "arrow.down.circle")
            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.blue)
        } else {
          Button {
            manager.downloadLlamaCpp(model)
          } label: {
            Label("Laden", systemImage: "arrow.down.circle.fill")
              .font(.system(size: 11.5, weight: .semibold))
          }
          .buttonStyle(PopoverActionButtonStyle(.primary))
          .disabled(!manager.system.diskFits(downloadGB: model.downloadGB))
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassTintedCard(accent: .blue, cornerRadius: 10)
  }

  // MARK: - Embedding model (semantic e-mail memory)

  private var embeddingModel: LlamaCppModelCatalog.Model {
    LlamaCppModelCatalog.defaultEmbeddingModel
  }

  private var embeddingSection: some View {
    let model = embeddingModel
    let installed = manager.isLlamaCppEmbeddingInstalled(model.id)
    let downloading = manager.isDownloadingLlamaCpp(model.id)
    let state = manager.llamaCppDownloads[model.id]
    return VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Embedding · E-Mail-Memory")
      Text("Optionales lokales Embedding-Modell für das semantische E-Mail-Gedächtnis.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          Image(systemName: installed ? "checkmark.circle.fill" : "arrow.down.circle")
            .font(.system(size: 13))
            .foregroundStyle(installed ? .green : .blue)
          VStack(alignment: .leading, spacing: 1) {
            Text(model.displayName).font(.system(size: 12, weight: .semibold))
            Text(
              installed
                ? "Lokal · 768 Dimensionen"
                : "\(SystemCapabilities.formatGB(model.downloadGB)) · noch nicht geladen"
            )
            .font(.system(size: 10)).foregroundStyle(.secondary)
          }
          Spacer()
          if installed {
            BlitzStatusPill(state: .ready, label: "Bereit")
            Button {
              manager.deleteLlamaCpp(model)
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(PopoverActionButtonStyle(.danger))
          } else if downloading {
            Button {
              manager.cancelLlamaCppDownload(model.id)
            } label: {
              Label("Stopp", systemImage: "xmark.circle")
            }
            .buttonStyle(PopoverActionButtonStyle(.secondary))
          } else {
            Button {
              manager.downloadLlamaCpp(model)
            } label: {
              Label("Laden", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(PopoverActionButtonStyle(.primary))
            .disabled(!manager.system.diskFits(downloadGB: model.downloadGB))
          }
        }
        if let state {
          HStack(spacing: 8) {
            ProgressView(value: state.fraction).controlSize(.small)
            Text(state.statusText)
              .font(.system(size: 10.5)).foregroundStyle(.secondary)
          }
        }
      }
      .padding(10)
      .liquidGlassCard(cornerRadius: 8)
    }
  }

  // MARK: - Active selection

  private func isActive(llamaCppModel model: LlamaCppModelCatalog.Model) -> Bool {
    appState.appSettings.selectedLocalLLM
      == LocalLLMSelection(runtime: .llamaCpp, modelID: model.id)
  }

  private func selectLlamaCpp(_ model: LlamaCppModelCatalog.Model) {
    appState.appSettings.selectedLocalLLM = LocalLLMSelection(runtime: .llamaCpp, modelID: model.id)
  }

  // MARK: - Banners & footer

  private func errorBanner(_ message: String) -> some View {
    Text(message)
      .font(.system(size: 11)).foregroundStyle(.red)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
  }

  private var footerHint: some View {
    Text(
      "Nichts verlässt deinen Mac. Modelle werden einmalig von Hugging Face geladen und danach lokal über llama.cpp ausgeführt."
    )
    .font(.system(size: 10)).foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }
}
