import SwiftUI

/// Step: small comfort opt-ins, one theme — how rede behaves around you. Everything here is
/// optional, default off, and changeable later in the System/Vokabular tabs. The memory toggle is
/// privacy-sensitive, so its caption stays sober and explicit (DESIGN.md).
struct ExtrasStepView: View {
  @Bindable var appState: AppState

  @State private var launchAtLoginService = LaunchAtLoginService()

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingStepHeader(
        systemImage: "slider.horizontal.3",
        accent: .cyan,
        title: "noch ein feinschliff?",
        subtitle: "alles optional, alles später änderbar. aber jetzt ist der beste moment dafür."
      )

      launchAtLoginCard
      soundCard
      memoryCard
    }
    .onAppear { launchAtLoginService.refresh() }
  }

  // MARK: - Launch at login

  private var launchAtLoginCard: some View {
    OnboardingCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          SectionLabel(text: "autostart")
          Spacer()
          Toggle(
            "rede automatisch starten",
            isOn: Binding(
              get: { launchAtLoginService.isEnabled },
              set: { launchAtLoginService.setEnabled($0) }
            )
          )
          .toggleStyle(.switch)
          .controlSize(.small)
          .labelsHidden()
          .accessibilityLabel("rede automatisch starten")
        }

        Text(launchAtLoginService.errorText ?? launchAtLoginService.helperText)
          .font(.system(size: 10.5))
          .foregroundStyle(
            launchAtLoginService.errorText == nil
              ? AnyShapeStyle(.secondary)
              : AnyShapeStyle(.red)
          )
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - Sound feedback

  private var soundCard: some View {
    OnboardingCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          SectionLabel(text: "töne")
          Spacer()
          Toggle(
            "töne bei start, fertig und fehler",
            isOn: $appState.appSettings.soundFeedbackEnabled
          )
          .toggleStyle(.switch)
          .controlSize(.small)
          .labelsHidden()
          .accessibilityLabel("töne bei start, fertig und fehler")
        }

        Text("kurze systemtöne als rückmeldung — fürs diktieren per hotkey, ohne hinzusehen.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if appState.appSettings.soundFeedbackEnabled {
          HStack(spacing: 8) {
            Text("anhören:")
              .font(.system(size: 10.5))
              .foregroundStyle(.secondary)
            Button("start") { EarconPlayer.play(.start) }
              .buttonStyle(PopoverActionButtonStyle(.quiet))
              .font(.system(size: 10.5, weight: .medium))
            Button("fertig") { EarconPlayer.play(.done) }
              .buttonStyle(PopoverActionButtonStyle(.quiet))
              .font(.system(size: 10.5, weight: .medium))
            Button("fehler") { EarconPlayer.play(.error) }
              .buttonStyle(PopoverActionButtonStyle(.quiet))
              .font(.system(size: 10.5, weight: .medium))
          }
        }
      }
    }
  }

  // MARK: - Archive & memory (privacy-sensitive opt-in)

  private var memoryCard: some View {
    OnboardingCard(accent: appState.isUnifiedMemoryEnabled ? .green : nil) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          SectionLabel(text: "archiv & memory")
          if appState.isUnifiedMemoryEnabled {
            BlitzStatusPill(state: .local, label: "lokal aktiv")
          }
          Spacer()
          Toggle("archiv und memory aktivieren", isOn: $appState.isUnifiedMemoryEnabled)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("archiv und memory aktivieren")
        }

        // Privacy copy stays sober and explicit: what is stored, where, and that it is opt-in.
        Text(
          "speichert transkripte als text-archiv und lernt wiederkehrende begriffe — alles nur "
            + "auf diesem Mac, kein audio, nichts geht online. aus = es wird nichts gespeichert."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if appState.isUnifiedMemoryEnabled {
          Text("feintuning (E-Mail-Memory, korrekturlernen) findest du im tab vokabular.")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}
