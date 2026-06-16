import XCTest

@testable import Rede

/// MEM-1 "Office Memory" foundation: pins the pure categorizer mapping (bundle id + role → coarse
/// category, unknown → other) and the bounded `ContextLogStore` (cap / append / clear) plus the
/// `topCategories` aggregation. No AX / AppKit state is touched — `PasteContext` is built directly.
final class PasteContextTests: XCTestCase {

  // MARK: - Categorizer: representative bundle ids per category

  func testCategorizesEmailBundles() {
    XCTAssertEqual(category("com.apple.mail"), .email)
    XCTAssertEqual(category("com.readdle.smartemail-Mac"), .email)  // Spark
    XCTAssertEqual(category("it.bloop.airmail2"), .email)
  }

  func testCategorizesChatBundles() {
    XCTAssertEqual(category("com.tinyspeck.slackmacgap"), .chat)
    XCTAssertEqual(category("WhatsApp"), .chat)
    XCTAssertEqual(category("com.apple.MobileSMS"), .chat)
    XCTAssertEqual(category("ru.keepcoder.Telegram"), .chat)
    XCTAssertEqual(category("com.hnc.Discord"), .chat)
  }

  func testCategorizesCodeBundles() {
    XCTAssertEqual(category("com.microsoft.VSCode"), .code)
    XCTAssertEqual(category("com.apple.dt.Xcode"), .code)
    XCTAssertEqual(category("com.sublimetext.4"), .code)
    XCTAssertEqual(category("com.jetbrains.intellij"), .code)
  }

  func testCategorizesBrowserBundles() {
    XCTAssertEqual(category("com.apple.Safari"), .browser)
    XCTAssertEqual(category("com.google.Chrome"), .browser)
    XCTAssertEqual(category("company.thebrowser.Browser"), .browser)  // Arc
    XCTAssertEqual(category("org.mozilla.firefox"), .browser)
  }

  func testCategorizesNotesBundles() {
    XCTAssertEqual(category("com.apple.Notes"), .notes)
    XCTAssertEqual(category("notion.id"), .notes)
    XCTAssertEqual(category("md.obsidian"), .notes)
  }

  func testCategorizesDocumentBundles() {
    XCTAssertEqual(category("com.apple.iWork.Pages"), .document)
    XCTAssertEqual(category("com.microsoft.Word"), .document)
    XCTAssertEqual(category("com.google.Docs"), .document)
  }

  func testCategorizesTerminalBundles() {
    XCTAssertEqual(category("com.apple.Terminal"), .terminal)
    XCTAssertEqual(category("com.googlecode.iterm2"), .terminal)
  }

  // MARK: - Role hints + unknown fallback

  func testUnknownBundleFallsBackToOther() {
    XCTAssertEqual(category("com.example.unknown"), .other)
    XCTAssertEqual(category(nil), .other)
    XCTAssertEqual(category(""), .other)
  }

  func testTerminalRoleHintWinsForUnknownBundle() {
    XCTAssertEqual(
      PasteContextCategory.categorize(bundleID: "com.example.unknown", role: "AXTerminal"),
      .terminal)
  }

  func testBrowserTextAreaStaysBrowser() {
    XCTAssertEqual(
      PasteContextCategory.categorize(bundleID: "com.apple.Safari", role: "AXTextArea"),
      .browser)
  }

  // MARK: - Web apps refined from the window title

  func testBrowserWindowTitleRefinesToWebApp() {
    XCTAssertEqual(
      PasteContextCategory.categorize(
        bundleID: "com.google.Chrome", role: nil,
        windowTitle: "Inbox (3) - you@gmail.com - Gmail"),
      .email)
    XCTAssertEqual(
      PasteContextCategory.categorize(
        bundleID: "com.apple.Safari", role: nil, windowTitle: "My tasks – Notion"),
      .notes)
    XCTAssertEqual(
      PasteContextCategory.categorize(
        bundleID: "com.google.Chrome", role: nil,
        windowTitle: "notabene-app · Pull requests · GitHub"),
      .code)
    XCTAssertEqual(
      PasteContextCategory.categorize(
        bundleID: "com.apple.Safari", role: nil, windowTitle: "general - Acme - Slack"),
      .chat)
  }

  func testBrowserWithoutKnownWebAppStaysBrowser() {
    XCTAssertEqual(
      PasteContextCategory.categorize(
        bundleID: "com.apple.Safari", role: nil, windowTitle: "Some random blog post"),
      .browser)
  }

  func testWindowTitleNeverOverridesADesktopAppBundle() {
    // A desktop app's bundle id always wins — a Mail window titled "… Gmail" stays email anyway,
    // and a code editor titled like a web app is not reclassified from its bundle.
    XCTAssertEqual(
      PasteContextCategory.categorize(
        bundleID: "com.apple.dt.Xcode", role: nil, windowTitle: "Inbox - Gmail"),
      .code)
  }

  // MARK: - Store: cap / append / clear

  @MainActor
  func testAppendInsertsNewestFirst() {
    let store = makeStore()
    store.append(makeContext(category: .email))
    store.append(makeContext(category: .chat))
    XCTAssertEqual(store.contexts.count, 2)
    XCTAssertEqual(store.contexts.first?.category, .chat)
  }

  @MainActor
  func testCapKeepsMostRecentEntries() {
    let store = makeStore()
    let total = ContextLogStore.maxEntries + 50
    for index in 0..<total {
      store.append(makeContext(category: .other, charCount: index))
    }
    XCTAssertEqual(store.contexts.count, ContextLogStore.maxEntries)
    // Newest-first: the last appended (highest index) sits at the front; the oldest are dropped.
    XCTAssertEqual(store.contexts.first?.charCount, total - 1)
  }

  @MainActor
  func testClearEmptiesTheStore() {
    let store = makeStore()
    store.append(makeContext(category: .email))
    store.clear()
    XCTAssertTrue(store.contexts.isEmpty)
  }

  // MARK: - Aggregation

  @MainActor
  func testTopCategoriesCountsDescending() {
    let store = makeStore()
    for _ in 0..<3 { store.append(makeContext(category: .email)) }
    for _ in 0..<5 { store.append(makeContext(category: .chat)) }
    store.append(makeContext(category: .code))

    let top = store.topCategories()
    XCTAssertEqual(top.first?.0, .chat)
    XCTAssertEqual(top.first?.1, 5)
    XCTAssertEqual(top[1].0, .email)
    XCTAssertEqual(top[1].1, 3)
    XCTAssertEqual(top.count, 3)
  }

  @MainActor
  func testTopCategoriesEmptyForEmptyStore() {
    XCTAssertTrue(makeStore().topCategories().isEmpty)
  }

  // MARK: - Helpers

  private func category(_ bundleID: String?) -> PasteContextCategory {
    PasteContextCategory.categorize(bundleID: bundleID, role: nil)
  }

  @MainActor
  private func makeStore() -> ContextLogStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ctxlog-\(UUID().uuidString).json")
    return ContextLogStore(fileURL: url)
  }

  private func makeContext(
    category: PasteContextCategory,
    charCount: Int = 0,
    date: Date = Date()
  ) -> PasteContext {
    PasteContext(
      date: date,
      appBundleID: "com.example.app",
      appName: "Example",
      windowTitle: "Title",
      elementRole: "AXTextField",
      category: category,
      mode: .transcription,
      charCount: charCount
    )
  }

  // MARK: - Secure-field detection (R4-FT-secure-guard)

  func testSecureFieldDetectedFromSubrole() {
    // The common case: a password field reports role AXTextField + subrole AXSecureTextField.
    XCTAssertTrue(
      PasteContextAXReader.isSecureFieldRole(role: "AXTextField", subrole: "AXSecureTextField"))
  }

  func testSecureFieldDetectedFromRole() {
    XCTAssertTrue(
      PasteContextAXReader.isSecureFieldRole(role: "AXSecureTextField", subrole: nil))
  }

  func testNonSecureFieldsAreNotFlagged() {
    XCTAssertFalse(
      PasteContextAXReader.isSecureFieldRole(role: "AXTextField", subrole: "AXContentList"))
    XCTAssertFalse(PasteContextAXReader.isSecureFieldRole(role: "AXTextArea", subrole: nil))
    XCTAssertFalse(PasteContextAXReader.isSecureFieldRole(role: nil, subrole: nil))
  }

  // MARK: - Retention (age-based pruning)

  @MainActor
  func testAppendDropsContextOlderThanRetention() {
    let store = makeStore()
    let stale = Date().addingTimeInterval(-Double(ContextLogStore.retentionDays + 5) * 86_400)
    store.append(makeContext(category: .email, date: stale))
    // A context older than the retention window is pruned the moment a mutation runs.
    XCTAssertTrue(store.contexts.isEmpty)
    store.append(makeContext(category: .chat))  // fresh survives
    XCTAssertEqual(store.contexts.count, 1)
    XCTAssertEqual(store.contexts.first?.category, .chat)
  }

  @MainActor
  func testLoadPrunesStaleContextsFromDisk() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ctxlog-retention-\(UUID().uuidString).json")
    let fresh = makeContext(category: .email)
    let stale = makeContext(
      category: .chat,
      date: Date().addingTimeInterval(-Double(ContextLogStore.retentionDays + 10) * 86_400))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([fresh, stale]).write(to: url)

    let store = ContextLogStore(fileURL: url)
    // The stale entry is dropped on load; only the fresh one remains.
    XCTAssertEqual(store.contexts.count, 1)
    XCTAssertEqual(store.contexts.first?.category, .email)
  }
}
