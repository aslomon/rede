import SwiftUI
import XCTest

@testable import Rede

private struct LiveCase {
  let name: String
  let snapshot: LiveTranscriptSnapshot
  let state: LiveDisplayState
}

private struct StatusCase {
  let name: String
  let status: UpdateService.Status
  let checks: Bool
  let busy: Bool
}

/// Opt-in renderer for the refresh UI states (acceptance label RENDERED). Skipped unless
/// `REDE_RENDER_DIR` names an existing directory; it only ever writes new PNGs there.
/// Limits: SwiftUI `ImageRenderer` output, not a screenshot of a running app — Liquid Glass and
/// materials are NOT rendered (a flat window color stands in), and nothing here exercises the
/// microphone, hotkeys or real windows.
@MainActor
final class RefreshRenderTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    guard let path = ProcessInfo.processInfo.environment["REDE_RENDER_DIR"], !path.isEmpty else {
      throw XCTSkip("set REDE_RENDER_DIR to render the refresh states")
    }
    directory = URL(fileURLWithPath: path, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw XCTSkip("REDE_RENDER_DIR must be an existing directory") }
  }

  private func render<Content: View>(
    _ name: String, width: CGFloat = 380, @ViewBuilder _ content: () -> Content
  ) throws {
    for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
      let view = content()
        .padding(16)
        .frame(width: width, alignment: .leading)
        .fontDesign(.rounded)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2
      let image = try XCTUnwrap(renderer.nsImage, name)
      let tiff = try XCTUnwrap(image.tiffRepresentation)
      let png = try XCTUnwrap(
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
      try png.write(
        to: directory.appendingPathComponent("\(name)-\(suffix).png"), options: .withoutOverwriting)
    }
  }

  // MARK: - Live pill

  func testRenderLivePillStates() throws {
    let talking = LiveTranscriptSnapshot(
      stableText: "Hallo Anna, ich wollte dir noch kurz sagen, dass der Termin",
      provisionalText: "am Montag um zehn stattfindet", revision: 5)
    let cases: [LiveCase] = [
      LiveCase(name: "connecting", snapshot: LiveTranscriptSnapshot(), state: .connecting),
      LiveCase(name: "listening", snapshot: LiveTranscriptSnapshot(), state: .streaming),
      LiveCase(name: "streaming", snapshot: talking, state: .streaming),
      LiveCase(name: "finishing", snapshot: talking, state: .finishing),
      LiveCase(name: "failed-note", snapshot: LiveTranscriptSnapshot(), state: .failed(.network))
    ]
    for item in cases {
      let (name, snapshot, state) = (item.name, item.snapshot, item.state)
      try render("pill-live-\(name)", width: LiquidGlass.pillExpandedWidth + 32) {
        RecordingPillLiveCard(
          live: LiveTranscriptModel(snapshot: snapshot, state: state), audioLevel: 0.4,
          accentColor: RedeBrand.violet, isHovering: false, onStop: {}, onCancel: {}
        )
        .background(
          RoundedRectangle(cornerRadius: LiquidGlass.pillCardRadius).fill(
            Color.primary.opacity(0.06)))
      }
    }
  }

  // MARK: - Updates

  func testRenderUpdateStatuses() throws {
    let when = Date(timeIntervalSince1970: 1_792_000_000)
    let statuses: [StatusCase] = [
      StatusCase(name: "never-checked", status: .idle(lastChecked: nil), checks: true, busy: false),
      StatusCase(name: "current", status: .idle(lastChecked: when), checks: true, busy: false),
      StatusCase(name: "checking", status: .checking, checks: true, busy: false),
      StatusCase(
        name: "downloading", status: .downloading(fraction: 0.42), checks: true, busy: false),
      StatusCase(name: "available", status: .available(version: "1.1"), checks: true, busy: false),
      StatusCase(name: "staged", status: .staged(version: "1.1"), checks: true, busy: false),
      StatusCase(
        name: "staged-waits-for-dictation", status: .staged(version: "1.1"), checks: true,
        busy: true),
      StatusCase(name: "failed-network", status: .failed(.network), checks: true, busy: false),
      StatusCase(
        name: "failed-signature", status: .failed(.invalidSignature), checks: true, busy: false),
      StatusCase(name: "checks-off", status: .idle(lastChecked: when), checks: false, busy: false)
    ]
    for item in statuses {
      let (name, status, checks, busy) = (item.name, item.status, item.checks, item.busy)
      let service = FakeUpdates()
      service.status = status
      service.automaticChecksEnabled = checks
      service.automaticDownloadsEnabled = checks
      let model = UpdateSettingsModel(service: service, updatesAvailable: true, isBusy: { busy })
      try render("updates-\(name)") {
        UpdatesSettingsContent(
          model: model, versionText: "rede 1.0 (1)", lastCheckText: "zuletzt geprüft: heute, 09:41"
        )
        .settingsGroupBackground()
      }
    }
  }

  func testRenderStagedInstallRefusedAndFooterHints() throws {
    let refused = FakeUpdates()
    refused.status = .staged(version: "1.1")
    refused.installResult = false
    let model = UpdateSettingsModel(service: refused, updatesAvailable: true, isBusy: { false })
    model.installNow()
    try render("updates-staged-install-refused") {
      UpdatesSettingsContent(
        model: model, versionText: "rede 1.0 (1)", lastCheckText: "zuletzt geprüft: heute, 09:41"
      )
      .settingsGroupBackground()
    }

    let cases: [(String, UpdateService.Status, Bool)] = [
      ("available", .available(version: "1.1"), false),
      ("staged", .staged(version: "1.1"), false),
      ("staged-busy", .staged(version: "1.1"), true),
      ("downloading", .downloading(fraction: 0.4), false)
    ]
    for (name, status, busy) in cases {
      let service = FakeUpdates()
      service.status = status
      service.availableUpdateVersion = "1.1"
      let hint = try XCTUnwrap(
        UpdateSettingsModel(service: service, updatesAvailable: true, isBusy: { busy }).footerHint)
      try render("footer-hint-\(name)") {
        HStack {
          Spacer()
          Button(hint.label) {}
            .buttonStyle(PopoverActionButtonStyle(.primary))
            .disabled(!hint.isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 410)
      }
    }
  }

  // MARK: - Online extras, notes, mode controls, badges

  func testRenderOnlineExtrasStates() throws {
    func content(secureLocal: Bool, live: Bool, routing: Bool, key: Bool) -> some View {
      var settings = AppSettings()
      settings.secureLocalModeEnabled = secureLocal
      settings.liveTranscriptionEnabled = live
      settings.purposeRoutingEnabled = routing
      return OnlineExtrasContent(
        live: LiveSettingsModel(settings: settings, hasAPIKey: key, microphoneAuthorized: true),
        routing: PurposeRoutingSettingsModel(settings: settings, hasAPIKey: key),
        secureLocal: secureLocal, onLive: { _ in }, onRouting: { _ in }, onFieldText: { _ in }
      )
      .settingsGroupBackground()
    }
    try render("extras-secure-local-stale-on") {
      content(secureLocal: true, live: true, routing: true, key: true)
    }
    try render("extras-online-off") {
      content(secureLocal: false, live: false, routing: false, key: true)
    }
    try render("extras-online-on") {
      content(secureLocal: false, live: true, routing: true, key: true)
    }
    try render("extras-online-no-key") {
      content(secureLocal: false, live: true, routing: true, key: false)
    }
  }

  func testRenderAutomatikNotesAndModeControls() throws {
    let notes: [(String, PurposeRoutingNote)] = [
      ("email", .detected(.email)), ("ai-prompt", .detected(.aiPrompt)),
      ("none", .noSpecialPurpose), ("unsure", .fellBack(.lowConfidence))
    ]
    for (name, note) in notes {
      try render("routing-note-\(name)") { PurposeRoutingNoteView(note: note) }
    }
    var luna = RewriteConfig()
    luna.reasoningEffort = .xhigh
    var settings = AppSettings()
    settings.secureLocalModeEnabled = true
    settings.purposeRoutingEnabled = true
    try render("mode-controls-secure-local") {
      VStack(alignment: .leading, spacing: 10) {
        RewriteEffortControl(model: ModelPickerModel(config: luna), onSelect: { _ in })
        AutomatikModeToggle(
          routing: PurposeRoutingSettingsModel(settings: settings, hasAPIKey: true),
          config: ModeConfig.default(for: .textImprover), rewriteBackend: .local, onChange: { _ in }
        )
      }
      .settingsGroupBackground()
    }
  }

  func testRenderSocialAutomatikToggle() throws {
    var settings = AppSettings()
    settings.secureLocalModeEnabled = false
    settings.purposeRoutingEnabled = true
    var social = ModeConfig.default(for: .emojiText)
    social.rewrite.purposeRouting = .automatic
    try render("mode-controls-social-automatik") {
      AutomatikModeToggle(
        routing: PurposeRoutingSettingsModel(settings: settings, hasAPIKey: true),
        config: social, rewriteBackend: .openai, onChange: { _ in }
      )
      .settingsGroupBackground()
    }
  }

  func testRenderLocalModelBadges() throws {
    let current = try XCTUnwrap(LlamaCppModelCatalog.currentModels.first)
    let legacy = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    let installed = LlamaCppModelCatalog.installedModel(
      from: LlamaCppModelStore.VerifiedManifest(
        modelID: "hf-ggml-org-gemma-4-e4b-it-gguf", fileName: "gemma-4-E4B-it-Q4_K_M.gguf",
        sha256: "90ce98129eb3e8cc57e62433d500c97c624b1e3af1fcc85dd3b55ad7e0313e9f",
        sizeBytes: 5_335_289_824, displayName: "Gemma 4 E4B · Q4_K_M", parameterSize: "E4B",
        quantization: "Q4_K_M", downloadURL: nil))
    try render("badges-models") {
      VStack(alignment: .leading, spacing: 10) {
        ForEach([current, installed, legacy], id: \.id) { model in
          HStack(spacing: 6) {
            Text(model.displayName).font(.system(size: 12.5, weight: .semibold))
            LocalModelBadgeRow(model: model)
          }
        }
      }
      .padding(12)
    }
  }
}
