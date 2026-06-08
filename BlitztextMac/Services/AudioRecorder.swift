import AVFoundation
import Observation

@Observable
@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
  /// Shown when the mic grant is denied/restricted — recording would silently capture nothing.
  static let micDeniedMessage = "Mikrofon nicht erlaubt — in den Systemeinstellungen aktivieren."
  /// Shown right after we trigger the one-time system prompt for an undecided grant. The user
  /// answers the dialog, then presses again — keeps `startRecording()` synchronous and honest.
  static let micPendingMessage = "Mikrofon-Zugriff erlauben und erneut starten."

  /// Pure status → optional error-message mapping, factored out so it can be unit-tested without
  /// touching `AVCaptureDevice`. `nil` means "proceed" (granted); `.notDetermined` returns the
  /// pending message (we kick off the system prompt separately before surfacing it).
  static func recordingBlockedMessage(for status: MicrophonePermissionService.Status) -> String? {
    switch status {
    case .granted: return nil
    case .denied: return micDeniedMessage
    case .notDetermined: return micPendingMessage
    }
  }

  /// Safety cap: a forgotten/runaway recording is auto-stopped after this many seconds so it
  /// can still be transcribed instead of growing unbounded (and blowing the upload limit).
  /// Configurable global (synced from `AppSettings.maxDictationMinutes` by `AppState`) so long
  /// dictations work — the cap only exists as a runaway guard, not a feature limit. Read when the
  /// timer is armed (at `startRecording`), so settings changes take effect on the next recording.
  static var maxRecordingDuration: TimeInterval = TimeInterval(
    AppSettings.defaultMaxDictationMinutes * 60)

  /// Opt-in global (synced from `AppSettings.silenceTrimmingEnabled`): when true, workflows run the
  /// finished recording through `SilenceTrimmer` before transcription to cut long speech pauses.
  static var silenceTrimmingEnabled: Bool = false

  /// Returns the file a workflow should transcribe: a pause-trimmed copy when silence trimming is
  /// enabled AND it actually shortened the audio, otherwise the untouched `original`. Callers MUST
  /// delete a returned URL that differs from `original` (it's a separate temp file). On any trimming
  /// failure this falls back to the original — trimming never costs the user their audio.
  static func audioForTranscription(original: URL) async -> URL {
    guard silenceTrimmingEnabled else { return original }
    return await SilenceTrimmer.trimmedAudio(at: original) ?? original
  }

  var isRecording = false
  var recordingURL: URL?
  var errorMessage: String?
  var audioLevel: Float = 0
  var lastRecordingDuration: TimeInterval = 0
  /// Set true when the max-duration cap fired and auto-stopped this recording. Lets the workflow
  /// surface a clear note while still transcribing the audio captured up to the cap.
  var didStopAtMaxDuration = false

  /// Invoked on the main thread when the max-duration cap fires while still recording. The owning
  /// workflow wires this to its own `stop()` so the captured audio is transcribed as usual.
  var onMaxDurationReached: (() -> Void)?

  private var audioRecorder: AVAudioRecorder?
  private var levelTimer: Timer?
  private var maxDurationTimer: Timer?
  private var currentFileURL: URL?

  private func makeRecordingURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("blitztext-\(UUID().uuidString).m4a")
  }

  func startRecording() {
    errorMessage = nil
    didStopAtMaxDuration = false
    lastRecordingDuration = 0
    recordingURL = nil
    if let currentFileURL {
      try? FileManager.default.removeItem(at: currentFileURL)
    }

    // Gate on mic authorization at record time: a denied/revoked grant produces a silent file,
    // and a never-asked grant must trigger the system prompt instead of recording into the void.
    let status = MicrophonePermissionService.currentStatus
    if let blocked = Self.recordingBlockedMessage(for: status) {
      if status == .notDetermined {
        Task { _ = await MicrophonePermissionService.request() }
      }
      errorMessage = blocked
      return
    }

    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    do {
      let fileURL = makeRecordingURL()
      currentFileURL = fileURL
      audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
      audioRecorder?.delegate = self
      audioRecorder?.isMeteringEnabled = true
      audioRecorder?.record()
      isRecording = true
      startMetering()
      startMaxDurationTimer()
    } catch {
      currentFileURL = nil
      errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
    }
  }

  func stopRecording() {
    stopMetering()
    stopMaxDurationTimer()
    lastRecordingDuration = audioRecorder?.currentTime ?? 0
    audioRecorder?.stop()
    isRecording = false
    recordingURL = currentFileURL
    currentFileURL = nil
    audioRecorder = nil
    audioLevel = 0
  }

  func discardRecording() {
    stopMaxDurationTimer()
    if let recordingURL {
      try? FileManager.default.removeItem(at: recordingURL)
      self.recordingURL = nil
    }

    if let currentFileURL {
      try? FileManager.default.removeItem(at: currentFileURL)
      self.currentFileURL = nil
    }
  }

  private func startMetering() {
    // The timer is scheduled on (and fires on) the main run loop, so assume MainActor isolation
    // synchronously rather than hopping through a Task every 0.05s.
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.audioRecorder?.updateMeters()
        let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
        self.audioLevel = max(0, min(1, (power + 50) / 50))
      }
    }
  }

  private func stopMetering() {
    levelTimer?.invalidate()
    levelTimer = nil
  }

  /// Arms the safety cap. Fires once at `maxRecordingDuration`; if still recording it flags the
  /// run and hands off to the workflow (via `onMaxDurationReached`) to stop + transcribe what was
  /// captured. The timer auto-invalidates on a normal stop/discard before it ever fires.
  private func startMaxDurationTimer() {
    maxDurationTimer = Timer.scheduledTimer(
      withTimeInterval: Self.maxRecordingDuration, repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.isRecording else { return }
        self.didStopAtMaxDuration = true
        self.errorMessage = "Aufnahme zu lang — automatisch gestoppt"
        self.onMaxDurationReached?()
      }
    }
  }

  private func stopMaxDurationTimer() {
    maxDurationTimer?.invalidate()
    maxDurationTimer = nil
  }

  // MARK: - AVAudioRecorderDelegate

  nonisolated func audioRecorderDidFinishRecording(
    _ recorder: AVAudioRecorder, successfully flag: Bool
  ) {
    if !flag {
      Task { @MainActor in
        self.errorMessage = "Aufnahme fehlgeschlagen"
      }
    }
  }
}
