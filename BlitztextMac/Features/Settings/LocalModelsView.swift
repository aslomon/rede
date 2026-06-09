import AppKit
import SwiftUI

/// The "Lokale Modelle" management page: shows this Mac's capabilities, a hardware-based
/// recommendation, the models already pulled into Ollama (with real on-disk sizes), and the
/// downloadable catalog with live progress. Hosted in its own window by `LocalModelsWindowController`.
struct LocalModelsView: View {
  @Bindable var appState: AppState
  @Bindable var manager: LocalModelManager
  @Environment(\.colorScheme) private var colorScheme
  @State private var customTag = ""
  @State private var pendingSelectionTag: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        if !manager.serverReachable { serverDownBanner }

        // Hardware facts first — the model recommendation and the per-model RAM fit are based on them.
        VStack(alignment: .leading, spacing: 8) {
          SectionLabel(text: "Dieser Mac")
          systemCard
        }

        // Engine 1 — Transcription (Whisper). Always local; independent of the Ollama server.
        WhisperModelsSection(appState: appState)

        Divider().opacity(0.4)

        // Engine 2 — Rewrite (Ollama LLM). Recommendation only until the first LLM is installed;
        // the long catalog + custom tag live behind a disclosure so they don't wall off the page.
        ollamaGroupLabel
        if let recommended = manager.recommended, llmInstalledModels.isEmpty {
          recommendationCard(recommended)
        }
        if !llmInstalledModels.isEmpty { installedSection }
        InfoDisclosure("Weitere Sprachmodelle laden") {
          VStack(alignment: .leading, spacing: 14) {
            catalogSection
            customSection
          }
        }

        Divider().opacity(0.4)

        // Engine 3 — Embedding (Ollama). Powers semantic e-mail memory.
        embeddingSection

        if let error = manager.lastError { errorBanner(error) }

        footerHint
      }
      .padding(16)
    }
    .frame(minWidth: 540, minHeight: 580)
    .task { await manager.refresh() }
    .onChange(of: manager.installed) { _, _ in
      selectPendingModelIfInstalled()
    }
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
      // Active-model pill removed from the header — it duplicated the "Aktiv" marker shown on the
      // model itself in the Ollama section below.
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

  @ViewBuilder
  private var activeModelPill: some View {
    if let activeModel {
      BlitzStatusPill(state: .ready, label: activeModel.name)
    } else {
      BlitzStatusPill(state: .warning, label: "Kein Modell")
    }
  }

  // MARK: - System card
  // spec #12: corner radius 10pt for section-level cards (unchanged — already 10pt)

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

  // MARK: - Recommendation
  // spec #9: .liquidGlassTintedCard(accent: .blue, cornerRadius: 10)
  //          This is the single permitted glass-on-card in LocalModelsView (floating window).

  private func recommendationCard(_ model: OllamaModelCatalog.Model) -> some View {
    let installed = manager.isInstalled(model.tag)
    let pulling = manager.isPulling(model.tag)
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
        Text("ca. \(SystemCapabilities.formatGB(model.downloadGB)) Download")
          .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        if installed {
          if isActive(tag: model.tag) {
            BlitzStatusPill(state: .ready, label: "Aktiv")
          } else {
            Button {
              selectInstalledModel(for: model.tag)
            } label: {
              Label("Nutzen", systemImage: "checkmark.circle")
            }
            .buttonStyle(PopoverActionButtonStyle(.secondary))
          }
        } else if pulling {
          Label("Wird geladen …", systemImage: "arrow.down.circle")
            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.blue)
        } else {
          Button {
            pullAndUse(model.tag)
          } label: {
            Label(loadButtonTitle, systemImage: "arrow.down.circle.fill")
              .font(.system(size: 11.5, weight: .semibold))
          }
          .buttonStyle(PopoverActionButtonStyle(.primary))
          .disabled(
            manager.isPreparingOllama || !manager.system.diskFits(downloadGB: model.downloadGB))
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassTintedCard(accent: .blue, cornerRadius: 10)
  }

  // MARK: - Installed
  // spec #12: .liquidGlassCard(cornerRadius: 8) on list-level rows

  /// Installed Ollama models that are rewrite LLMs — the embedding model is excluded because it has
  /// its own engine group below, so it never shows up twice.
  private var llmInstalledModels: [OllamaService.InstalledModel] {
    manager.installed.filter { !isEmbeddingModel($0) }
  }

  private var installedSection: some View {
    let models = llmInstalledModels
    let totalGB = models.reduce(0.0) { $0 + $1.sizeGB }
    return VStack(alignment: .leading, spacing: 8) {
      SectionLabel(
        text: "Installiert (\(models.count) · \(SystemCapabilities.formatGB(totalGB)))")
      ForEach(models) { record in
        installedRow(record)
      }
    }
  }

  private func installedRow(_ record: OllamaService.InstalledModel) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 13)).foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 1) {
        Text(record.name).font(.system(size: 12, weight: .semibold))
        if let params = record.parameterSize {
          Text([params, record.quantization].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
      Spacer()
      if isEmbeddingModel(record) {
        // An embedding model is not a rewrite model — never offer "Nutzen" (which sets the LLM).
        BlitzStatusPill(state: .muted, label: "Embedding")
      } else if isActive(record: record) {
        BlitzStatusPill(state: .ready, label: "Aktiv")
      } else {
        Button {
          select(record)
        } label: {
          Label("Nutzen", systemImage: "checkmark.circle")
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))
      }
      Text(SystemCapabilities.formatGB(record.sizeGB))
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
      DeleteModelButton(
        displayName: record.name,
        deleteTag: record.name,
        freedSizeGB: record.sizeGB,
        manager: manager
      )
    }
    .padding(10)
    // spec #12: .liquidGlassCard(cornerRadius: 8) for list-level rows
    .liquidGlassCard(cornerRadius: 8)
  }

  // MARK: - Catalog

  private var catalogSection: some View {
    // Only show models that actually run on this Mac's RAM — anything that doesn't fit (fit ==
    // .tooLarge) is hidden so it can't be downloaded into a model that won't load.
    let runnable = OllamaModelCatalog.models.filter {
      manager.system.fit(forRuntimeRAMGB: $0.estimatedRuntimeRAMGB) != .tooLarge
    }
    return VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Verfügbare Modelle")
      ForEach(runnable) { model in
        LocalModelRowView(
          model: model,
          manager: manager,
          isActive: isActive(tag: model.tag),
          onUseInstalled: { selectInstalledModel(for: model.tag) },
          onPullAndUse: { pullAndUse(model.tag) }
        )
      }
    }
  }

  // MARK: - Section grouping

  /// Visually separates the Ollama rewrite/embedding block from the Whisper block above, so the
  /// unified window reads as three clearly-labelled engine groups rather than one long list.
  private var ollamaGroupLabel: some View {
    SectionLabel(text: "Umschreiben · Sprachmodell (Ollama)")
  }

  // MARK: - Embedding model

  /// The embedding model that powers semantic e-mail memory. Managed here too so every local model
  /// type — transcription, rewrite, embedding — can be loaded, re-downloaded and deleted in one place.
  private var embeddingTag: String {
    let configured = appState.selectedEmbeddingModelName
    return configured.isEmpty ? OllamaEmbeddingProvider.defaultModelID : configured
  }

  private var embeddingSection: some View {
    let tag = embeddingTag
    let installed = manager.isInstalled(tag)
    let pulling = manager.isPulling(tag)
    return VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Embedding · E-Mail-Memory")
      HStack(spacing: 10) {
        Image(systemName: installed ? "checkmark.circle.fill" : "arrow.down.circle")
          .font(.system(size: 13))
          .foregroundStyle(installed ? .green : .blue)
        VStack(alignment: .leading, spacing: 1) {
          Text(tag).font(.system(size: 12, weight: .semibold))
          Text(installed ? "Lokal · für semantisches E-Mail-Memory" : "Nicht geladen")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        Spacer()
        embeddingActions(tag: tag, installed: installed, pulling: pulling)
      }
      .padding(10)
      .liquidGlassCard(cornerRadius: 8)
    }
  }

  @ViewBuilder
  private func embeddingActions(tag: String, installed: Bool, pulling: Bool) -> some View {
    if pulling {
      Label("Wird geladen …", systemImage: "arrow.down.circle")
        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.blue)
    } else if installed {
      Button {
        manager.prepareOllamaAndPull(tag)
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(PopoverIconButtonStyle(.quiet))
      .help("Neu laden")
      DeleteModelButton(
        displayName: tag,
        deleteTag: tag,
        freedSizeGB: manager.installedRecord(for: tag)?.sizeGB,
        manager: manager
      )
    } else {
      Button {
        manager.prepareOllamaAndPull(tag)
      } label: {
        Label("Laden", systemImage: "arrow.down.circle.fill")
          .font(.system(size: 11.5, weight: .semibold))
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
      .disabled(manager.isPreparingOllama)
    }
  }

  // MARK: - Custom tag

  private var customSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionLabel(text: "Anderes Modell laden")
      HStack(spacing: 8) {
        TextField("z. B. llama3.1:70b", text: $customTag)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 11.5))
          .onSubmit(loadCustom)
        Button(loadButtonTitle, action: loadCustom)
          .buttonStyle(PopoverActionButtonStyle(.primary))
          .font(.system(size: 11.5, weight: .semibold))
          .disabled(
            customTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || manager.isPreparingOllama)
      }
      Text("Beliebiger Ollama-Tag von ollama.com/library.")
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }
  }

  private func loadCustom() {
    let tag = customTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !tag.isEmpty else { return }
    pullAndUse(tag)
    customTag = ""
  }

  // MARK: - Active selection

  private var activeModel: OllamaService.InstalledModel? {
    let selected = appState.appSettings.selectedLocalLLMModelName.trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard !selected.isEmpty else { return nil }
    return manager.installed.first { OllamaService.isInstalled(selected, in: [$0.name]) }
  }

  private func isActive(record: OllamaService.InstalledModel) -> Bool {
    activeModel?.id == record.id
  }

  /// Whether this installed Ollama record is the configured embedding model (so the row labels it
  /// "Embedding" instead of offering "Nutzen", which would mis-assign it as the rewrite LLM).
  private func isEmbeddingModel(_ record: OllamaService.InstalledModel) -> Bool {
    OllamaService.isInstalled(embeddingTag, in: [record.name])
  }

  private func isActive(tag: String) -> Bool {
    guard let activeModel else { return false }
    return OllamaService.isInstalled(tag, in: [activeModel.name])
  }

  private func select(_ record: OllamaService.InstalledModel) {
    appState.appSettings.selectedLocalLLMModelName = record.name
  }

  private func selectInstalledModel(for tag: String) {
    guard
      let record = manager.installed.first(where: { OllamaService.isInstalled(tag, in: [$0.name]) })
    else { return }
    select(record)
  }

  private func pullAndUse(_ tag: String) {
    pendingSelectionTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    manager.prepareOllamaAndPull(tag)
    selectPendingModelIfInstalled()
  }

  private func selectPendingModelIfInstalled() {
    guard let pendingSelectionTag else { return }
    guard
      let record = manager.installed.first(where: {
        OllamaService.isInstalled(pendingSelectionTag, in: [$0.name])
      })
    else { return }
    select(record)
    self.pendingSelectionTag = nil
  }

  // MARK: - Banners
  // spec #11: at most two buttons; when installed: 'Ollama starten' (.warning) + icon-only refresh;
  //           when not installed: 'Ollama installieren' (.warning) + Link with SF Symbol.

  private var serverDownBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Ollama läuft gerade nicht", systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
      Text(
        manager.ollamaAppInstalled
          ? "Starte die Ollama-App, dann kannst du Modelle direkt hier laden."
          : "Blitztext kann Ollama laden, installieren und danach das Modell installieren."
      )
      .font(.system(size: 11)).foregroundStyle(.secondary)
      if let installState = manager.ollamaInstallState {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(installState.statusText)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
      }
      // spec #11: two buttons max
      HStack(spacing: 8) {
        if manager.ollamaAppInstalled {
          // installed: primary action + icon-only refresh
          Button("Ollama starten") { manager.prepareOllama() }
            .buttonStyle(PopoverActionButtonStyle(.warning))
            .font(.system(size: 11.5, weight: .semibold))
            .disabled(manager.isPreparingOllama)

          Button {
            Task { await manager.refresh() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(PopoverIconButtonStyle(.quiet))
          .disabled(manager.isRefreshing || manager.isPreparingOllama)
          .help("Erneut prüfen")
        } else {
          // not installed: install action + download-page link
          Button("Ollama installieren") { manager.prepareOllama() }
            .buttonStyle(PopoverActionButtonStyle(.warning))
            .font(.system(size: 11.5, weight: .semibold))
            .disabled(manager.isPreparingOllama)

          Link(destination: URL(string: "https://ollama.com/download")!) {
            Label("Download-Seite", systemImage: "arrow.up.right.square")
              .font(.system(size: 11, weight: .medium))
          }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassInfoBanner(accent: .orange, cornerRadius: 10)
  }

  private func errorBanner(_ message: String) -> some View {
    Text(message)
      .font(.system(size: 11)).foregroundStyle(.red)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
  }

  // MARK: - Footer
  // spec #10: multi-sentence hint moved behind InfoDisclosure; only single caption line visible.

  private var footerHint: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Nichts verlässt deinen Mac.")
        .font(.system(size: 10)).foregroundStyle(.secondary)

      InfoDisclosure("Ollama & Datenschutz") {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "Modelle werden über deine lokale Ollama-Installation geladen und geteilt. "
              + "Nichts verlässt deinen Mac."
          )
          Text(
            "Abgebrochene Downloads bleiben erhalten und werden beim erneuten Laden fortgesetzt."
          )
        }
      }
    }
  }

  private func openOllamaDownloadPage() {
    guard let url = URL(string: "https://ollama.com/download") else { return }
    NSWorkspace.shared.open(url)
  }

  private var loadButtonTitle: String {
    if manager.serverReachable { return "Laden & nutzen" }
    return manager.ollamaAppInstalled ? "Starten & nutzen" : "Installieren & nutzen"
  }
}
