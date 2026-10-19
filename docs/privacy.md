# Privacy Notes

rede macOS Preview does not include a hosted backend.

When you use the online workflows, your Mac sends data directly to OpenAI:

- audio recordings for transcription
- transcribed or typed text for rewriting
- custom terms and prompt context if you configured them

When **Sicherer Lokaler Modus** is enabled and compatible local models are installed, transcription runs through WhisperKit/CoreML and rewriting runs through the bundled llama.cpp runtime on your Mac (a local server on `localhost`). In that mode the app avoids sending dictation audio or rewrite text to OpenAI.

You are responsible for your OpenAI account, API usage, costs, and data handling.

## Optional Live Transcription and Purpose Routing

Both new master switches are off by default. These features send data directly to OpenAI only
when explicitly enabled and permitted by the selected workflow. Secure local mode blocks both
features before a remote request or connection is opened.

| Feature | Destination | Data and activation |
| --- | --- | --- |
| Live transcription | `wss://api.openai.com/v1/realtime?intent=transcription` | Microphone audio streamed **while you speak**, plus configured languages and keywords. Requires the Live opt-in, a remote transcription backend, an API key, microphone authorization, and secure local mode off. |
| Automatic purpose routing (Decisions) | `https://api.openai.com/v1/decisions`, model `gpt-6-luna` | Bounded dictation and allowed app/text context. Requires the routing master switch, automatic routing enabled for the current mode, OpenAI rewriting, an API key, and secure local mode off. |

Cancel stops future Live transfer; audio already sent cannot be recalled. If Live cannot produce
a usable final transcript, the existing file-transcription fallback may send the recorded audio
through the configured remote transcription path.

Decisions inputs are limited to 2,000 characters of dictation, 800 characters of selected text,
800 characters of focused-field text, and 80 characters of app name, with a 4,000-character total
limit. Routing does not read screenshots, window titles, file contents, or whole-window text.
Focused secure/password fields skip routing entirely. Focused-field text has its own opt-out;
enabling routing does not enable other context, memory, or semantic-email switches.

An uncertain result, refusal, timeout, or error leaves routing neutral and the existing rewrite
behavior applies. We do not claim that OpenAI will not store Decisions inputs.

## Update Checks

The app can check for new versions once per day and on manual request (Einstellungen → System →
Updates). The check downloads the public release feed (`appcast.xml`) of this project over HTTPS.
Automatic downloads are enabled by default for every installation without a stored Sparkle
preference, including existing installations. Existing explicit choices are preserved. When enabled,
Sparkle also downloads and verifies the signed update archive
from the project's GitHub releases in the background and prepares it for installation when the app
quits. This does not force the app to quit during dictation. A manual update can also offer an
install-and-relaunch action through Sparkle's standard dialog.

- Transmitted: a standard HTTPS request; the user agent contains the app name and version.
- Not transmitted: no system profile, no hardware data, no identifiers, no usage data. The app
  disables Sparkle's `sendsSystemProfile` before starting the updater, including previously stored
  consent, and its delegate permits no system-profile keys even if an external preference changes.
  `SUEnableSystemProfiling` stays absent to hide Sparkle's optional profiling prompt; that key alone
  does not control whether profile data is sent.
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

Workflow output may also be placed on your clipboard so it can be pasted into another app. Auto-paste marks the clipboard entry as concealed for compatible clipboard managers, and the final generated text stays on the clipboard after every insertion attempt, including successful auto-paste, until you copy something else. This allows later manual reuse with Cmd+V. Clipboard managers, macOS, or other apps may still observe clipboard contents while they are present.

The app uses the system TLS trust store for OpenAI and Hugging Face requests. It does not currently pin certificates. A user-installed or managed root certificate can therefore affect HTTPS trust decisions on that Mac.

Settings such as custom prompts, custom terms, and context are stored in local app support storage as plain JSON. Do not put secrets into those fields.

## Offline Scope

Transcription can run locally through WhisperKit/CoreML. Rewriting can run locally through the bundled llama.cpp runtime when a local GGUF model is selected or secure local mode forces local processing. Semantic email memory uses a local llama.cpp embedding server. Both run on `localhost` only.

If a mode is configured for OpenAI processing, text and prompt context for that mode are sent to OpenAI. If semantic email memory is enabled for an OpenAI-backed email mode, retrieved background snippets are included in that prompt context.

Archive, semantic email memory, context logging, and improvement detection are opt-in. Runs targeting secure/password fields are skipped for archive, context, improvement, and semantic-memory storage.

## Sensitive Content

Do not use this preview with confidential, regulated, or highly sensitive content unless you have reviewed the code, your OpenAI settings, and your legal/privacy requirements.
