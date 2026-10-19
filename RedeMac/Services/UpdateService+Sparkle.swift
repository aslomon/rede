import Foundation

#if SPARKLE_ENABLED
  import Sparkle
  // MARK: - SPUUpdaterDelegate

  extension UpdateService: SPUUpdaterDelegate {
    nonisolated func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
      []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
      foundUpdate(version: item.displayVersionString)
    }

    func updater(
      _ updater: SPUUpdater,
      willDownloadUpdate item: SUAppcastItem,
      with request: NSMutableURLRequest
    ) {
      startedDownload()
    }

    func updater(
      _ updater: SPUUpdater,
      willInstallUpdateOnQuit item: SUAppcastItem,
      immediateInstallationBlock install: @escaping () -> Void
    ) -> Bool {
      stageInstallation(version: item.displayVersionString, install: install)
      return true
    }

    func updater(
      _ updater: SPUUpdater,
      shouldPostponeRelaunchForUpdate item: SUAppcastItem,
      untilInvokingBlock install: @escaping () -> Void
    ) -> Bool {
      postponeRelaunchIfBusy(version: item.displayVersionString, install: install)
    }

    nonisolated func updater(
      _ updater: SPUUpdater,
      didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
      error: Error?
    ) {
      Task { @MainActor [weak self] in
        self?.finishedUpdateCycle(error: error)
      }
    }
  }

  // MARK: - SPUStandardUserDriverDelegate (gentle reminders)

  /// rede is an `LSUIElement` menu bar app: scheduled update alerts must not steal focus
  /// while the user dictates. Sparkle's gentle-reminders flow lets us surface a quiet hint in the
  /// popover instead; the standard Sparkle UI only appears for user-initiated checks (or once the
  /// user clicks the hint).
  extension UpdateService: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
      _ update: SUAppcastItem,
      andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
      // Only let Sparkle pop its window when the app already has focus (practically never for a
      // menu bar app); otherwise we take over and show the quiet popover hint.
      MainActor.assumeIsolated { shouldShowScheduledUpdate(immediateFocus: immediateFocus) }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
      _ handleShowingUpdate: Bool,
      forUpdate update: SUAppcastItem,
      state: SPUUserUpdateState
    ) {
      guard !state.userInitiated else { return }
      let version = update.displayVersionString
      Task { @MainActor [weak self] in
        self?.foundUpdate(version: version)
      }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
      Task { @MainActor [weak self] in
        self?.clearUpdateReminder()
      }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
      Task { @MainActor [weak self] in
        self?.clearUpdateReminder()
      }
    }
  }
#endif
