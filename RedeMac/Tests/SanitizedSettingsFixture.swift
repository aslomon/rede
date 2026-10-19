import Foundation
import XCTest

/// Content-identical copy (keys re-sorted) of the root-provided sanitized settings fixture:
/// personal names, prompts and context are placeholders; model identifiers and schema are
/// preserved. It is the ONLY installed-settings shape the tests may use — private settings are
/// never read.
enum SanitizedSettingsFixture {
  static let containerJSON = #"""
    {
      "app": {
        "archiveEnabled": true,
        "dictationDictionary": {
          "replacements": []
        },
        "didMigrateToModeConfigs": true,
        "dismissedImprovementSuggestionKeys": [],
        "fuzzyCorrectionEnabled": false,
        "hadAccessibilityGrant": true,
        "hasAutoSelectedFastLocalModel": true,
        "hasCompletedOnboarding": false,
        "hasSeenOnboarding": false,
        "hotkeyMode": "toggle",
        "hotkeys": {},
        "improvementDetectionEnabled": true,
        "maxDictationMinutes": 30,
        "memoryContextEnabled": true,
        "modeOrder": [
          "transcription",
          "localTranscription",
          "textImprover",
          "dampfAblassen",
          "emojiText"
        ],
        "modes": {
          "dampfAblassen": {
            "isEnabled": true,
            "kind": "transcribeThenRewrite",
            "rewrite": {
              "context": "",
              "emojiDensity": "mittel",
              "modelID": "gpt-5.4",
              "replyContextMode": "off",
              "rewriteBackend": "openai",
              "semanticEmailEnrichmentLevel": "medium",
              "showTwoVariants": true,
              "systemPrompt": "[Synthetic fixture text]",
              "tone": "neutral",
              "useAutomaticFieldContext": true,
              "useMemoryContext": true,
              "useSemanticEmailMemory": false
            },
            "slot": "dampfAblassen",
            "userName": "[Synthetic fixture text]"
          },
          "emojiText": {
            "isEnabled": true,
            "kind": "transcribeThenEmoji",
            "rewrite": {
              "context": "",
              "emojiDensity": "mittel",
              "modelID": "gpt-4o-mini",
              "replyContextMode": "off",
              "rewriteBackend": "openai",
              "semanticEmailEnrichmentLevel": "medium",
              "showTwoVariants": true,
              "systemPrompt": "",
              "tone": "neutral",
              "useAutomaticFieldContext": false,
              "useMemoryContext": false,
              "useSemanticEmailMemory": false
            },
            "slot": "emojiText",
            "userName": "[Synthetic fixture text]"
          },
          "localTranscription": {
            "isEnabled": true,
            "kind": "transcribeOnly",
            "rewrite": {
              "context": "",
              "emojiDensity": "mittel",
              "modelID": "gpt-4o",
              "replyContextMode": "off",
              "rewriteBackend": "openai",
              "semanticEmailEnrichmentLevel": "medium",
              "showTwoVariants": false,
              "systemPrompt": "",
              "tone": "neutral",
              "useAutomaticFieldContext": false,
              "useMemoryContext": false,
              "useSemanticEmailMemory": false
            },
            "slot": "localTranscription",
            "userName": "[Synthetic fixture text]"
          },
          "textImprover": {
            "isEnabled": true,
            "kind": "transcribeThenRewrite",
            "rewrite": {
              "context": "",
              "emojiDensity": "mittel",
              "modelID": "gpt-5.4",
              "replyContextMode": "off",
              "rewriteBackend": "openai",
              "semanticEmailEnrichmentLevel": "medium",
              "showTwoVariants": true,
              "systemPrompt": "[Synthetic fixture text]",
              "tone": "neutral",
              "useAutomaticFieldContext": true,
              "useMemoryContext": true,
              "useSemanticEmailMemory": true
            },
            "slot": "textImprover",
            "userName": "[Synthetic fixture text]"
          },
          "transcription": {
            "isEnabled": true,
            "kind": "transcribeOnly",
            "rewrite": {
              "context": "",
              "emojiDensity": "mittel",
              "modelID": "gpt-4o",
              "replyContextMode": "off",
              "rewriteBackend": "openai",
              "semanticEmailEnrichmentLevel": "medium",
              "showTwoVariants": false,
              "systemPrompt": "",
              "tone": "neutral",
              "useAutomaticFieldContext": false,
              "useMemoryContext": false,
              "useSemanticEmailMemory": false
            },
            "slot": "transcription",
            "userName": "[Synthetic fixture text]"
          }
        },
        "modesSchemaVersion": 4,
        "secureLocalModeEnabled": false,
        "selectedEmbeddingModelName": "nomic-embed-text-v1.5-q8",
        "selectedLocalLLM": {
          "modelID": "hf-ggml-org-gemma-4-e4b-it-gguf",
          "runtime": "llamaCpp"
        },
        "selectedLocalLLMModelName": "",
        "selectedLocalTranscriptionModelName": "openai_whisper-large-v3-v20240930_turbo_632MB",
        "semanticEmailMemoryEnabled": true,
        "silenceTrimmingEnabled": false,
        "soundFeedbackEnabled": true,
        "userDisplayName": "[Synthetic fixture text]"
      },
      "dampfAblassen": {
        "customName": "",
        "systemPrompt": "[Synthetic fixture text]"
      },
      "emojiText": {
        "customName": "",
        "emojiDensity": "mittel"
      },
      "textImprovement": {
        "context": "",
        "customName": "",
        "customTerms": [],
        "systemPrompt": "",
        "tone": "neutral"
      },
      "transcription": {
        "language": "de"
      }
    }
    """#

  /// The `app` block, i.e. what `AppSettings` decodes from disk.
  static func appJSON() throws -> Data {
    let container = try JSONSerialization.jsonObject(with: Data(containerJSON.utf8))
    let app = try XCTUnwrap((container as? [String: Any])?["app"])
    return try JSONSerialization.data(withJSONObject: app)
  }
}
