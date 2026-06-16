import XCTest

@testable import Rede

@MainActor
final class AutomaticContextTests: XCTestCase {

  func testCuratedRewriteModesDefaultToAutomaticWindowContext() {
    XCTAssertFalse(RewriteConfig().useAutomaticFieldContext)
    XCTAssertTrue(ModeConfig.default(for: .textImprover).rewrite.useAutomaticFieldContext)
    XCTAssertTrue(ModeConfig.default(for: .dampfAblassen).rewrite.useAutomaticFieldContext)
    XCTAssertFalse(ModeConfig.default(for: .emojiText).rewrite.useAutomaticFieldContext)
  }

  func testDisabledAutomaticFieldContextFlagsAdvancedDisclosure() {
    var email = ModeConfig.default(for: .textImprover)
    email.rewrite.useAutomaticFieldContext = false

    XCTAssertTrue(email.isAdvancedNonDefault)
  }

  func testAutomaticFieldContextBlockIsInjectedWhenEnabled() throws {
    var rewrite = RewriteConfig(systemPrompt: "Write the message.")
    rewrite.useAutomaticFieldContext = true
    let context = AutomaticRewriteContext(
      text: "Previous email says the invoice is missing.",
      appBundleID: "com.apple.mail",
      appName: "Mail",
      windowTitle: "Invoice thread"
    )

    let prompt = LLMService.rewriteSystemPrompt(
      rewrite,
      customTerms: [],
      selection: nil,
      automaticContext: context,
      memory: nil
    )

    XCTAssertTrue(prompt.contains("Aktueller Arbeitskontext"))
    XCTAssertTrue(prompt.contains("Previous email says the invoice is missing."))
    XCTAssertTrue(prompt.contains("Mail"))
    XCTAssertTrue(prompt.contains("Invoice thread"))
  }

  func testAutomaticFieldContextIsIgnoredWhenDisabled() {
    let rewrite = RewriteConfig(systemPrompt: "Write the message.")
    let context = AutomaticRewriteContext(
      text: "Do not include me.",
      appBundleID: nil,
      appName: nil,
      windowTitle: nil
    )

    let prompt = LLMService.rewriteSystemPrompt(
      rewrite,
      customTerms: [],
      selection: nil,
      automaticContext: context,
      memory: nil
    )

    XCTAssertFalse(prompt.contains("Aktueller Arbeitskontext"))
    XCTAssertFalse(prompt.contains("Do not include me."))
  }

  func testAutomaticFieldContextWindowPrefersCursorRelativeText() {
    let text = String(repeating: "A", count: 2500)
      + " CURSOR_CONTEXT "
      + String(repeating: "B", count: 2500)
    let window = SelectionContextService.automaticFieldContextWindow(
      fullText: text,
      selectedRange: NSRange(location: 2500, length: 0),
      maxChars: 1200
    )

    XCTAssertLessThanOrEqual(window.utf16.count, 1200)
    XCTAssertTrue(window.contains("CURSOR_CONTEXT"))
    XCTAssertFalse(window.hasPrefix(String(repeating: "A", count: 1500)))
  }

  func testAutomaticWindowContextUsesWindowTextWhenFocusedFieldIsEmpty() {
    let context = SelectionContextService.automaticWindowContext(
      focusedFieldText: "",
      selectedRange: nil,
      windowText: "Subject: Re: Appointment\nOriginal message body",
      maxChars: 1000
    )

    XCTAssertTrue(context.contains("Subject: Re: Appointment"))
    XCTAssertTrue(context.contains("Original message body"))
  }

  func testAutomaticWindowContextMergesFocusedFieldWithWindowText() {
    let context = SelectionContextService.automaticWindowContext(
      focusedFieldText: "I can make the appointment.",
      selectedRange: NSRange(location: 27, length: 0),
      windowText: "Subject: Re: Appointment\nPlease be there ten minutes early.",
      maxChars: 1000
    )

    XCTAssertTrue(context.contains("I can make the appointment."))
    XCTAssertTrue(context.contains("Please be there ten minutes early."))
  }

  func testAutomaticWindowContextDeduplicatesFocusedFieldAlreadyInWindowText() {
    let context = SelectionContextService.automaticWindowContext(
      focusedFieldText: "Please be there ten minutes early.",
      selectedRange: nil,
      windowText: "Subject: Re: Appointment\nPlease be there ten minutes early.",
      maxChars: 1000
    )

    XCTAssertEqual(context.components(separatedBy: "Please be there ten minutes early.").count, 2)
  }

  func testRewriteContextDiagnosticSummarizesPresenceWithoutLeakingText() {
    let selection = SelectionContext(
      selectedText: "",
      surroundingText: "quoted mail body that must not be logged",
      appBundleID: "com.apple.mail"
    )
    let automaticContext = AutomaticRewriteContext(
      text: "visible reply context that must not be logged",
      appBundleID: "com.apple.mail",
      appName: "Mail",
      windowTitle: "Re: Private appointment"
    )
    var config = ModeConfig.default(for: .textImprover)
    config.rewrite.replyContextMode = .replyUsingContext
    config.rewrite.useAutomaticFieldContext = true

    let diagnostic = RewriteContextCaptureDiagnostic(
      modeID: "textImprover",
      launchSource: .hotkeyBackground,
      config: config,
      selection: selection,
      automaticContext: automaticContext
    )
    let line = diagnostic.logLine

    XCTAssertTrue(line.contains("selectionEnabled=true"), line)
    XCTAssertTrue(line.contains("selectionPresent=true"), line)
    XCTAssertTrue(line.contains("selectionSurroundingChars=40"), line)
    XCTAssertTrue(line.contains("automaticEnabled=true"), line)
    XCTAssertTrue(line.contains("automaticPresent=true"), line)
    XCTAssertTrue(line.contains("automaticChars=45"), line)
    XCTAssertTrue(line.contains("automaticWindowTitlePresent=true"), line)
    XCTAssertFalse(line.contains("quoted mail body"))
    XCTAssertFalse(line.contains("visible reply context"))
    XCTAssertFalse(line.contains("Private appointment"))
  }
}
