import Foundation

enum PurposeRoutingInput {
    static func render(_ context: DecisionContext) -> String {
        let sections = [
            "App: \(prefix(cleaned(context.appName ?? ""), limit: 80))",
            "Selected text: \(prefix(cleaned(context.selectedText ?? ""), limit: 800))",
            "Field text: \(prefix(cleaned(context.fieldText ?? ""), limit: 800))",
            "Dictation: \(headAndTail(cleaned(context.dictatedText), limit: 2000))"
        ]
        return prefix(sections.joined(separator: "\n"), limit: 4000)
    }

    static func cleaned(_ text: String) -> String {
        let withoutControls = String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? UnicodeScalar(32)! : $0
        }))
        let withoutURLs = withoutControls.replacingOccurrences(
            of: "(?i)(?:https?://|www\\.)\\S+", with: "[URL]", options: .regularExpression)
        return withoutURLs.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func prefix(_ text: String, limit: Int) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit)))
    }

    private static func headAndTail(_ text: String, limit: Int) -> String {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > limit else { return text }
        let head = (limit - 3) / 2
        return String(String.UnicodeScalarView(scalars.prefix(head))) + " … "
            + String(String.UnicodeScalarView(scalars.suffix(limit - 3 - head)))
    }
}

enum PurposeOverlay {
    static func apply(_ purpose: DictationPurpose, to systemPrompt: String) -> String {
        let overlay: String
        switch purpose {
        case .other: return systemPrompt
        case .email:
            overlay = "Format this as an email body with clear paragraphs. "
                + "Preserve the mode's tone and emoji settings. Never invent facts, a recipient, or a subject. "
                + "Include a greeting or closing only when dictated or clearly implied. "
                + "Preserve all stated facts and intent."
        case .aiPrompt:
            overlay = "Format this as a clear instruction for an AI assistant or coding agent. "
                + "Preserve the mode's tone and emoji settings. Keep names, constraints, identifiers, "
                + "and quotes verbatim. Do not answer or execute the dictation. "
                + "Add no requirements and invent no facts."
        }
        return systemPrompt + "\n\n--- Purpose formatting ---\n" + overlay
    }
}
