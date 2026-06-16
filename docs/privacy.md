# Privacy Notes

rede macOS Preview does not include a hosted backend.

When you use the online workflows, your Mac sends data directly to OpenAI:

- audio recordings for transcription
- transcribed or typed text for rewriting
- custom terms and prompt context if you configured them

When **Sicherer Lokaler Modus** is enabled and compatible local models are installed, transcription runs through WhisperKit/CoreML and rewriting runs through the bundled llama.cpp runtime on your Mac (a local server on `localhost`). In that mode the app avoids sending dictation audio or rewrite text to OpenAI.

You are responsible for your OpenAI account, API usage, costs, and data handling.

## Update Checks

The app can check for new versions once per day and on manual request (Einstellungen → System →
Updates). The check downloads the public release feed (`appcast.xml`) of this project over HTTPS
and, only when you choose to install, the signed update archive from the project's GitHub releases.

- Transmitted: a standard HTTPS request; the user agent contains the app name and version.
- Not transmitted: no system profile, no hardware data, no identifiers, no usage data. Sparkle's
  optional system profiling is disabled and absent from the build (`SUEnableSystemProfiling` is
  never set).
- The daily check can be turned off in Einstellungen → System → Updates; the manual check stays
  available. Disabling it stops all scheduled update traffic.
- Update archives are verified against the app's pinned EdDSA public key before extraction
  (`SUVerifyUpdateBeforeExtraction`), independent of Apple notarization.

## Local Data

The app stores:

- your OpenAI API key in the user's macOS Keychain
- workflow settings in local app support storage
- optional WhisperKit/CoreML model folders in local app support storage
- optional text archive, context logs, improvement logs, and semantic email-memory records when you enable those features
- semantic email-memory embeddings generated locally through a bundled llama.cpp embedding model; the store keeps finished email text plus vectors for up to 30 days
- temporary audio files while a transcription is being processed; the app attempts to delete each recording when the workflow ends or is cancelled

Workflow output may also be placed on your clipboard so it can be pasted into another app. Auto-paste marks the clipboard entry as concealed for compatible clipboard managers, but the generated text intentionally remains on the clipboard as a fallback if automatic paste is blocked. Clipboard managers, macOS, or other apps may still observe clipboard contents while they are present.

The app uses the system TLS trust store for OpenAI and Hugging Face requests. It does not currently pin certificates. A user-installed or managed root certificate can therefore affect HTTPS trust decisions on that Mac.

Settings such as custom prompts, custom terms, and context are stored in local app support storage as plain JSON. Do not put secrets into those fields.

## Offline Scope

Transcription can run locally through WhisperKit/CoreML. Rewriting can run locally through the bundled llama.cpp runtime when a local GGUF model is selected or secure local mode forces local processing. Semantic email memory uses a local llama.cpp embedding server. Both run on `localhost` only.

If a mode is configured for OpenAI processing, text and prompt context for that mode are sent to OpenAI. If semantic email memory is enabled for an OpenAI-backed email mode, retrieved background snippets are included in that prompt context.

Archive, semantic email memory, context logging, and improvement detection are opt-in. Runs targeting secure/password fields are skipped for archive, context, improvement, and semantic-memory storage.

## Sensitive Content

Do not use this preview with confidential, regulated, or highly sensitive content unless you have reviewed the code, your OpenAI settings, and your legal/privacy requirements.
