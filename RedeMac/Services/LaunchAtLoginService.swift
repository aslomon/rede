import Foundation
import Observation
import ServiceManagement

@Observable
@MainActor
final class LaunchAtLoginService {
    var isEnabled = false
    var helperText = "rede startet nicht automatisch."
    var errorText: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status

        switch status {
        case .enabled:
            isEnabled = true
            helperText = "rede startet beim anmelden automatisch."
        case .notFound:
            isEnabled = false
            helperText = "rede muss in /Applications liegen, damit der anmeldestart verf\u{00FC}gbar ist."
        case .requiresApproval:
            isEnabled = true
            helperText = "noch in den systemeinstellungen freigeben."
        case .notRegistered:
            isEnabled = false
            helperText = "rede startet nicht automatisch."
        @unknown default:
            isEnabled = false
            helperText = "auf diesem Mac nicht verfügbar."
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorText = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            errorText = enabled
                ? "anmeldestart konnte nicht aktiviert werden. lege rede in /Applications und versuche es erneut."
                : "anmeldestart konnte nicht deaktiviert werden. bitte versuche es erneut."
        }
    }
}
