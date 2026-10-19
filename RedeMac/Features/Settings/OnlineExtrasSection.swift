import SwiftUI

/// Models tab → "online-extras": the two opt-in features that send data to OpenAI while you work.
/// Both are OFF by default, both stay visible (but disabled, with the reason) in secure-local mode,
/// and a value stored earlier stays stored but inert there. Logic: `LiveSettingsModel` and
/// `PurposeRoutingSettingsModel`; this view renders them and holds the German copy.
struct OnlineExtrasSection: View {
  @Bindable var appState: AppState

  var body: some View {
    let live = LiveSettingsModel(
      settings: appState.appSettings, hasAPIKey: appState.hasOpenAIKey,
      microphoneAuthorized: MicrophonePermissionService.currentStatus.isGranted)
    let routing = PurposeRoutingSettingsModel(
      settings: appState.appSettings, hasAPIKey: appState.hasOpenAIKey)
    OnlineExtrasContent(
      live: live, routing: routing,
      secureLocal: appState.appSettings.secureLocalModeEnabled,
      onLive: { appState.appSettings = live.setting($0) },
      onRouting: { appState.appSettings = routing.settingEnabled($0) },
      onFieldText: { appState.appSettings = routing.settingFieldText($0) })
  }
}

/// Pure rendering of the two switches; every change goes out through a closure.
struct OnlineExtrasContent: View {
  let live: LiveSettingsModel
  let routing: PurposeRoutingSettingsModel
  let secureLocal: Bool
  let onLive: (Bool) -> Void
  let onRouting: (Bool) -> Void
  let onFieldText: (Bool) -> Void

  private var anythingActive: Bool { live.isEffective || (routing.isEnabled && routing.canToggle) }

  var body: some View {
    SettingsSection(
      "online-extras", icon: "cloud",
      trailing: { statusPill },
      content: {
        liveRow
        Divider().opacity(0.4)
        automatikRow
      })
  }

  private var statusPill: some View {
    RedeStatusPill(
      state: secureLocal ? .local : (anythingActive ? .online : .muted),
      label: secureLocal ? "im lokalmodus aus" : (anythingActive ? "an" : "aus"))
  }

  // MARK: - Live

  private var liveRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle(
        isOn: Binding(
          get: { live.isOn },
          set: onLive)
      ) {
        Label("live-text beim sprechen", systemImage: "waveform.badge.mic")
          .labelStyle(QuietToggleLabelStyle())
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .disabled(!live.canToggle)

      if let block = live.block {
        Text(block.copy)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
      InfoDisclosure("was wird gesendet?") {
        Text(
          "während du sprichst, geht dein audio live an OpenAI, und der text erscheint in der "
            + "pille. eingefügt wird erst am ende, wie bisher. wenn du abbrichst, stoppt die "
            + "übertragung, aber audio, das schon gesendet wurde, lässt sich nicht zurückholen. "
            + "klappt live nicht, transkribiert rede danach die aufnahme wie gewohnt."
        )
      }
    }
  }

  // MARK: - Automatik

  private var automatikRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle(
        isOn: Binding(
          get: { routing.isEnabled },
          set: onRouting)
      ) {
        Label("automatik: zweck erkennen", systemImage: "wand.and.stars.inverse")
          .labelStyle(QuietToggleLabelStyle())
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .disabled(!routing.canToggle)

      Toggle(
        isOn: Binding(
          get: { routing.includesFieldText },
          set: onFieldText)
      ) {
        Label("text aus dem aktuellen feld mitsenden", systemImage: "text.cursor")
          .labelStyle(QuietToggleLabelStyle())
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .disabled(!routing.canToggle || !routing.isEnabled)
      .padding(.leading, 20)

      if let block = routing.block {
        Text(block.copy)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      } else if routing.isEnabled {
        Text("jetzt noch pro modus einschalten (modi-tab).")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
      InfoDisclosure("was wird gesendet?") {
        Text(
          "automatik erkennt, ob dein diktat eine e-mail oder ein ki-prompt ist, und passt das "
            + "umschreiben daran an. dafür gehen das diktat (gekürzt), der app-name, markierter "
            + "text und der text im aktuellen feld (gekürzt) an OpenAI. in passwortfeldern läuft "
            + "nichts. den feldtext schickt rede nur in modi, die feldkontext ohnehin nutzen. "
            + "wie lange OpenAI diese anfragen aufbewahrt, steuert rede nicht. ist die erkennung "
            + "unsicher, läuft alles wie gewohnt. sie ist ein hilfsmittel, keine garantie."
        )
      }
    }
  }
}
