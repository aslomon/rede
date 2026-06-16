import AppKit
import ApplicationServices

/// Reads the user's current text selection (and a little surrounding text) from the
/// frontmost app via the Accessibility API. Reuses the existing Accessibility grant.
/// Best-effort: many WebKit/Electron apps don't expose AXSelectedText — returns nil then.
@MainActor
enum SelectionContextService {
  private static let maxSelectedChars = 4000
  // DR-4: cursor-relatives Fenster statt ganzes Feld — kleineres Budget aus Datenschutzgründen.
  static let maxSurroundingChars = 600
  static let maxAutomaticFieldContextChars = 2_000
  static let maxAutomaticWindowContextChars = 8_000
  private static let maxWindowTraversalNodes = 500
  private static let maxWindowTraversalDepth = 12

  /// Captures the current selection synchronously. Call while the target app is still frontmost.
  static func capture() -> SelectionContext? {
    guard AXIsProcessTrusted() else { return nil }

    let systemWide = AXUIElementCreateSystemWide()
    guard let focused = copyElement(systemWide, kAXFocusedUIElementAttribute) else { return nil }
    let appBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    return captureSelection(from: focused, appBundleID: appBundleID)
  }

  /// Captures selection from a known app process. This is the safer path for menu-bar starts,
  /// because the click/popover can change the system-wide focused element before recording starts.
  static func capture(pid: pid_t, appBundleID: String?) -> SelectionContext? {
    guard AXIsProcessTrusted() else { return nil }
    let app = AXUIElementCreateApplication(pid)
    guard let focused = copyElement(app, kAXFocusedUIElementAttribute) else { return nil }
    return captureSelection(from: focused, appBundleID: appBundleID)
  }

  private static func captureSelection(
    from focused: AXUIElement,
    appBundleID: String?
  ) -> SelectionContext? {
    let selected = copyString(focused, kAXSelectedTextAttribute)
    let fullText = copyString(focused, kAXValueAttribute)
    let selectedRange = copySelectedRange(focused)

    let selectedText = clamp(selected, to: maxSelectedChars)
    // DR-4: nur ein Fenster um den Cursor/die Auswahl senden, nicht das ganze Feld.
    let surroundingText = surroundingWindow(
      fullText: fullText, selectedRange: selectedRange, maxChars: maxSurroundingChars)

    let context = SelectionContext(
      selectedText: selectedText,
      surroundingText: selectedText.isEmpty ? surroundingText : "",
      appBundleID: appBundleID
    )
    return context.isEmpty ? nil : context
  }

  /// Captures transient working context without requiring a selection. It first reads the focused
  /// field, then scans readable text in the focused window. Secure fields are skipped by the
  /// caller-provided target snapshot and again during window traversal. Best-effort: apps that do
  /// not expose text through AX simply return nil.
  static func captureAutomaticFieldContext(
    appBundleID: String?,
    appName: String?,
    windowTitle: String?,
    isSecureField: Bool
  ) -> AutomaticRewriteContext? {
    guard !isSecureField, AXIsProcessTrusted() else { return nil }

    let systemWide = AXUIElementCreateSystemWide()
    guard let focused = copyElement(systemWide, kAXFocusedUIElementAttribute) else { return nil }

    return captureAutomaticFieldContext(
      focused: focused,
      window: copyElement(systemWide, kAXFocusedWindowAttribute),
      appBundleID: appBundleID,
      appName: appName,
      windowTitle: windowTitle
    )
  }

  /// Captures automatic context from a known app process. Prefer this for menu-bar starts, where
  /// system-wide focus may already have moved away from the user's original target.
  static func captureAutomaticFieldContext(
    pid: pid_t,
    appBundleID: String?,
    appName: String?,
    windowTitle: String?,
    isSecureField: Bool
  ) -> AutomaticRewriteContext? {
    guard !isSecureField, AXIsProcessTrusted() else { return nil }

    let app = AXUIElementCreateApplication(pid)
    guard let focused = copyElement(app, kAXFocusedUIElementAttribute) else { return nil }
    let window = copyElement(app, kAXFocusedWindowAttribute)
    return captureAutomaticFieldContext(
      focused: focused,
      window: window,
      appBundleID: appBundleID,
      appName: appName,
      windowTitle: windowTitle
    )
  }

  private static func captureAutomaticFieldContext(
    focused: AXUIElement,
    window: AXUIElement?,
    appBundleID: String?,
    appName: String?,
    windowTitle: String?
  ) -> AutomaticRewriteContext? {
    let fullText = copyString(focused, kAXValueAttribute)
    let selectedRange = copySelectedRange(focused)
    let windowText = window.map { automaticWindowText($0, maxChars: maxAutomaticWindowContextChars) } ?? ""
    let text = automaticWindowContext(
      focusedFieldText: fullText,
      selectedRange: selectedRange,
      windowText: windowText,
      maxChars: maxAutomaticWindowContextChars
    )

    let context = AutomaticRewriteContext(
      text: text,
      appBundleID: appBundleID,
      appName: appName,
      windowTitle: windowTitle
    )
    return context.isEmpty ? nil : context
  }

  // MARK: - Windowing (testbar, rein)

  /// DR-4: liefert ein cursor-relatives Fenster um `selectedRange` (max. `maxChars` Zeichen,
  /// grob zentriert auf die Auswahl). Ist die Range nil/ungültig, wird wie bisher auf die
  /// ersten `maxChars` Zeichen zurückgefallen. Arbeitet auf der UTF-16-View, um die
  /// `NSRange`-Semantik der Accessibility-API zu treffen, und ist gegen Out-of-Bounds gesichert.
  static func surroundingWindow(
    fullText: String, selectedRange: NSRange?, maxChars: Int = 600
  ) -> String {
    let units = Array(fullText.utf16)
    let total = units.count
    guard total > 0, maxChars > 0 else { return "" }

    // Ungültige / fehlende Range → erste maxChars Zeichen (heutiges Verhalten, kleineres Budget).
    guard let range = selectedRange,
      range.location != NSNotFound,
      range.location >= 0,
      range.length >= 0,
      range.location <= total
    else {
      return clamp(String(decoding: units.prefix(maxChars), as: UTF16.self), to: maxChars)
    }

    if total <= maxChars { return clamp(fullText, to: maxChars) }

    let rangeEnd = min(range.location + range.length, total)
    // Restbudget gleichmäßig vor/hinter die Auswahl legen, dann an die Stringgrenzen klemmen.
    let budget = max(0, maxChars - (rangeEnd - range.location))
    var start = range.location - budget / 2
    var end = rangeEnd + (budget - budget / 2)
    if start < 0 {
      end += -start
      start = 0
    }
    if end > total {
      start -= end - total
      end = total
    }
    start = max(0, start)
    let window = String(decoding: units[start..<end], as: UTF16.self)
    return clamp(window, to: maxChars)
  }

  /// Larger cursor-relative window for automatic field context. Kept separate from
  /// `surroundingWindow` so reply/edit selection stays on its tighter privacy budget.
  static func automaticFieldContextWindow(
    fullText: String, selectedRange: NSRange?, maxChars: Int = 2_000
  ) -> String {
    surroundingWindow(fullText: fullText, selectedRange: selectedRange, maxChars: maxChars)
  }

  /// Builds the transient rewrite context from the focused field and the broader focused window.
  /// The focused field remains cursor-relative; the window scan contributes additional visible text
  /// such as quoted email content. Exact contained duplicates are removed before the final cap.
  static func automaticWindowContext(
    focusedFieldText: String,
    selectedRange: NSRange?,
    windowText: String,
    maxChars: Int = maxAutomaticWindowContextChars
  ) -> String {
    let focusedContext = automaticFieldContextWindow(
      fullText: focusedFieldText,
      selectedRange: selectedRange,
      maxChars: maxAutomaticFieldContextChars
    )
    return mergeContextParts([focusedContext, windowText], maxChars: maxChars)
  }

  // MARK: - Focused window scan

  private static func automaticWindowText(_ window: AXUIElement, maxChars: Int) -> String {
    var result: [String] = []
    var visited = Set<UInt>()
    var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
    var index = 0

    while index < queue.count,
      index < maxWindowTraversalNodes,
      joinedCount(result) < maxChars
    {
      let item = queue[index]
      index += 1

      let identity = UInt(CFHash(item.element))
      guard !visited.contains(identity) else { continue }
      visited.insert(identity)

      guard !isSecureElement(item.element) else { continue }

      if let text = readableText(from: item.element) {
        appendDistinct(text, to: &result)
      }

      guard item.depth < maxWindowTraversalDepth else { continue }
      for child in children(of: item.element) {
        queue.append((child, item.depth + 1))
      }
    }

    return clamp(result.joined(separator: "\n"), to: maxChars)
  }

  private static func readableText(from element: AXUIElement) -> String? {
    let role = copyString(element, kAXRoleAttribute).lowercased()
    guard isReadableRole(role) else { return nil }

    for attribute in [
      kAXValueAttribute,
      kAXTitleAttribute,
      kAXDescriptionAttribute,
      kAXHelpAttribute,
    ] {
      let text = copyString(element, attribute)
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return text
      }
    }
    return nil
  }

  private static func isReadableRole(_ role: String) -> Bool {
    role.contains("statictext")
      || role.contains("textfield")
      || role.contains("textarea")
      || role.contains("webarea")
      || role.contains("group")
      || role.contains("scrollarea")
      || role.contains("outline")
      || role.contains("row")
      || role.contains("cell")
      || role.contains("heading")
      || role.contains("link")
  }

  private static func isSecureElement(_ element: AXUIElement) -> Bool {
    let role = copyString(element, kAXRoleAttribute)
    let subrole = copyString(element, kAXSubroleAttribute)
    return PasteContextAXReader.isSecureFieldRole(role: role, subrole: subrole)
  }

  // MARK: - Context merge

  private static func mergeContextParts(_ parts: [String], maxChars: Int) -> String {
    var result: [String] = []
    for part in parts {
      appendDistinct(part, to: &result)
    }
    return clamp(result.joined(separator: "\n\n"), to: maxChars)
  }

  private static func appendDistinct(_ text: String, to result: inout [String]) {
    let cleaned = normalizedContextText(text)
    guard !cleaned.isEmpty else { return }

    if result.contains(where: { existing in
      let normalizedExisting = normalizedForComparison(existing)
      let normalizedCleaned = normalizedForComparison(cleaned)
      return normalizedExisting == normalizedCleaned
        || normalizedExisting.contains(normalizedCleaned)
        || normalizedCleaned.contains(normalizedExisting)
    }) {
      return
    }

    result.removeAll { existing in
      normalizedForComparison(cleaned).contains(normalizedForComparison(existing))
    }
    result.append(cleaned)
  }

  private static func normalizedContextText(_ text: String) -> String {
    text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  private static func normalizedForComparison(_ text: String) -> String {
    text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .lowercased()
  }

  private static func joinedCount(_ values: [String]) -> Int {
    values.reduce(0) { $0 + $1.count }
  }

  // MARK: - AX helpers

  /// Liest `kAXSelectedTextRangeAttribute` als `NSRange`. Gibt nil zurück, wenn das Attribut
  /// fehlt, kein `AXValue` vom Typ `.cfRange` ist oder die Extraktion scheitert. Kein Force-Unwrap.
  private static func copySelectedRange(_ element: AXUIElement) -> NSRange? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      element, kAXSelectedTextRangeAttribute as CFString, &value)
    guard result == .success, let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    // value ist als CFTypeRef bereits ein AXValue; getrennt prüfen wir den Wert-Typ unten.
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var cfRange = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &cfRange) else { return nil }
    guard cfRange.location >= 0, cfRange.length >= 0 else { return nil }
    return NSRange(location: cfRange.location, length: cfRange.length)
  }

  private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else { return nil }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
  }

  private static func copyElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value, CFGetTypeID(value) == CFArrayGetTypeID() else {
      return []
    }

    let array = unsafeDowncast(value, to: CFArray.self)
    let count = CFArrayGetCount(array)
    guard count > 0 else { return [] }

    var elements: [AXUIElement] = []
    elements.reserveCapacity(count)
    for index in 0..<count {
      guard let pointer = CFArrayGetValueAtIndex(array, index) else { continue }
      let child = unsafeBitCast(pointer, to: AXUIElement.self)
      elements.append(child)
    }
    return elements
  }

  private static func children(of element: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var seen = Set<UInt>()
    for attribute in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, kAXRowsAttribute] {
      for child in copyElements(element, attribute) {
        let identity = UInt(CFHash(child))
        guard !seen.contains(identity) else { continue }
        seen.insert(identity)
        result.append(child)
      }
    }
    return result
  }

  private static func copyString(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value, CFGetTypeID(value) == CFStringGetTypeID() else {
      return ""
    }
    return (value as! CFString) as String
  }

  private static func clamp(_ text: String, to limit: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit))
  }
}
