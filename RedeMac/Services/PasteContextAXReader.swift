import AppKit
import ApplicationServices

/// Reads the focused window title + focused-element role of a target app via the Accessibility
/// API. Best-effort and fully guarded: when Accessibility is off (or the app exposes nothing),
/// every field is nil. Reuses the existing Accessibility grant; never blocks the paste path —
/// callers invoke it only at target-capture time, before rede activates.
@MainActor
enum PasteContextAXReader {
  /// Upper bound on the focused field value we re-read for MEM-2. A focused-element value can be an
  /// entire document; beyond this we skip (return nil) rather than copy megabytes onto the main
  /// actor and run the O(n²) anchor scan in `ImprovementDiff`. Generous enough for emails/chats.
  static let maxValueLength = 20_000

  /// Window title + focused-element role + whether the focused element is a SECURE (password)
  /// field. All best-effort; `(nil, nil, false)` when Accessibility is off / nothing is exposed.
  /// `isSecureField` lets callers treat a password field as sensitive (skip logging, etc.).
  static func read(pid: pid_t) -> (windowTitle: String?, elementRole: String?, isSecureField: Bool)
  {
    guard AXIsProcessTrusted() else { return (nil, nil, false) }

    let app = AXUIElementCreateApplication(pid)
    let windowTitle = focusedWindowTitle(app)
    let (elementRole, isSecure) = focusedElementRoleAndSecurity(app)
    return (windowTitle, elementRole, isSecure)
  }

  /// Re-reads the focused element's text VALUE for the given process, for the opt-in
  /// "Verbesserungs-Erkennung" (MEM-2). Returns `nil` unless the focused element is a text-like
  /// field (role contains TextField / TextArea) AND exposes a non-empty `kAXValueAttribute`. Fully
  /// guarded: Accessibility off, no focused element, or a non-text role all yield `nil` (skip).
  static func readFocusedValue(pid: pid_t) -> String? {
    guard AXIsProcessTrusted() else { return nil }

    let app = AXUIElementCreateApplication(pid)
    guard let element = copyElement(app, kAXFocusedUIElementAttribute) else { return nil }

    let role = copyString(element, kAXRoleAttribute).lowercased()
    guard role.contains("textfield") || role.contains("textarea") else { return nil }

    let value = copyString(element, kAXValueAttribute)
    // Skip oversized fields (whole documents): the improvement diff is best-effort, so bounding the
    // input here keeps both the copy and the downstream anchor scan off the main actor's critical path.
    guard !value.isEmpty, value.count <= maxValueLength else { return nil }
    return value
  }

  // MARK: - AX helpers

  private static func focusedWindowTitle(_ app: AXUIElement) -> String? {
    guard let window = copyElement(app, kAXFocusedWindowAttribute) else { return nil }
    let title = copyString(window, kAXTitleAttribute)
    return title.isEmpty ? nil : title
  }

  /// Focused-element role plus a secure-field flag. A macOS password field reports role
  /// `AXTextField` with subrole `AXSecureTextField` (some report it as the role), so both are
  /// checked case-insensitively.
  private static func focusedElementRoleAndSecurity(_ app: AXUIElement) -> (
    role: String?, isSecure: Bool
  ) {
    guard let element = copyElement(app, kAXFocusedUIElementAttribute) else { return (nil, false) }
    let role = copyString(element, kAXRoleAttribute)
    let subrole = copyString(element, kAXSubroleAttribute)
    return (role.isEmpty ? nil : role, isSecureFieldRole(role: role, subrole: subrole))
  }

  /// Pure predicate (no AX state) so the secure-field rule is unit-testable: a macOS password field
  /// carries the `AXSecureTextField` marker on its role or subrole. `nonisolated` — no MainActor.
  nonisolated static func isSecureFieldRole(role: String?, subrole: String?) -> Bool {
    let marker = "securetextfield"
    return (role ?? "").lowercased().contains(marker)
      || (subrole ?? "").lowercased().contains(marker)
  }

  private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else { return nil }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  private static func copyString(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value, CFGetTypeID(value) == CFStringGetTypeID() else {
      return ""
    }
    let string = unsafeDowncast(value, to: CFString.self) as String
    return string.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
