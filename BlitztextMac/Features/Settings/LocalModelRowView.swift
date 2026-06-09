import SwiftUI

/// One catalog model row: name, purpose, planning metadata (download size, est. RAM, fit badge),
/// and a state-aware trailing control (Laden / Fortschritt+Abbrechen / Installiert+Entfernen).
struct LocalModelRowView: View {
  let model: OllamaModelCatalog.Model
  let manager: LocalModelManager
  let isActive: Bool
  let onUseInstalled: () -> Void
  let onPullAndUse: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  private var fit: SystemCapabilities.Fit {
    manager.system.fit(forRuntimeRAMGB: model.estimatedRuntimeRAMGB)
  }

  private var diskFits: Bool {
    manager.system.diskFits(downloadGB: model.downloadGB)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(model.displayName)
          .font(.system(size: 12.5, weight: .semibold))

        Text(model.blurb)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        metaRow
      }

      Spacer(minLength: 8)

      trailingControl
        .frame(width: 116, alignment: .trailing)
    }
    .padding(10)
    // spec #12: .liquidGlassCard(cornerRadius: 8) replaces manual RoundedRectangle.fill + overlay
    .liquidGlassCard(cornerRadius: 8)
  }

  // MARK: - Meta (size · RAM · fit)

  private var metaRow: some View {
    HStack(spacing: 8) {
      metaLabel("internaldrive", "ca. \(SystemCapabilities.formatGB(model.downloadGB))")
      metaLabel("memorychip", "~\(SystemCapabilities.formatGB(model.estimatedRuntimeRAMGB)) RAM")
      fitBadge
    }
  }

  private func metaLabel(_ symbol: String, _ text: String) -> some View {
    HStack(spacing: 3) {
      Image(systemName: symbol).font(.system(size: 9))
      Text(text).font(.system(size: 10, weight: .medium))
    }
    .foregroundStyle(.secondary)
  }

  private var fitBadge: some View {
    let (text, color): (String, Color) = {
      switch fit {
      case .comfortable: return ("Passt locker", .green)
      case .tight: return ("Knapp", .orange)
      case .tooLarge: return ("Zu groß", .red)
      }
    }()
    return Text(text)
      .font(.system(size: 9.5, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(color.opacity(0.12)))
  }

  // MARK: - Trailing control

  @ViewBuilder private var trailingControl: some View {
    if let pull = manager.pulls[model.tag] {
      pullingControl(pull)
    } else if manager.isInstalled(model.tag) {
      installedControl
    } else {
      loadControl
    }
  }

  private func pullingControl(_ pull: LocalModelManager.PullUIState) -> some View {
    VStack(alignment: .trailing, spacing: 4) {
      if let fraction = pull.fraction {
        ProgressView(value: fraction).frame(width: 110)
      } else {
        ProgressView().controlSize(.small)
      }
      Text(pull.statusText)
        .font(.system(size: 9.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Button("Abbrechen") { manager.cancelPull(model.tag) }
        .buttonStyle(PopoverActionButtonStyle(.secondary))
        .font(.system(size: 10, weight: .medium))
        .help(
          "Abbrechen — der Teil-Download bleibt erhalten und wird beim erneuten Laden fortgesetzt.")
    }
  }

  private var installedControl: some View {
    VStack(alignment: .trailing, spacing: 4) {
      if isActive {
        BlitzStatusPill(state: .ready, label: "Aktiv")
      } else {
        Button {
          onUseInstalled()
        } label: {
          Label("Nutzen", systemImage: "checkmark.circle")
        }
        // Secondary so "activate an installed model" reads clearly different from the filled,
        // primary "Laden" (download) action.
        .buttonStyle(PopoverActionButtonStyle(.secondary))
      }
      // Size is already shown in metaRow on the left — the "… auf Disk" line here was a duplicate.
      let record = manager.installedRecord(for: model.tag)
      DeleteModelButton(
        displayName: model.displayName,
        deleteTag: record?.name ?? model.tag,
        freedSizeGB: record?.sizeGB,
        manager: manager
      )
    }
  }

  @ViewBuilder private var loadControl: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Button {
        onPullAndUse()
      } label: {
        Label(loadButtonTitle, systemImage: "arrow.down.circle")
          .font(.system(size: 11.5, weight: .semibold))
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
      .disabled(!diskFits || manager.isPreparingOllama)

      if !diskFits {
        Text("Zu wenig Speicher")
          .font(.system(size: 9.5))
          .foregroundStyle(.red.opacity(0.85))
      } else if !manager.serverReachable {
        Text(manager.ollamaAppInstalled ? "Ollama startet mit" : "inkl. Ollama")
          .font(.system(size: 9.5))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var loadButtonTitle: String {
    if manager.serverReachable { return "Laden & nutzen" }
    return manager.ollamaAppInstalled ? "Starten & laden" : "Installieren & laden"
  }
}
