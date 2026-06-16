# Implementation Plan: Update Service & Own-App Distribution (`rede`)

## Status (2026-06-10)

- **Phase 1 (in-app updater): code-complete** — `UpdateService` (gentle reminders), Updates
  section in System settings, popover footer/gear hint, Sparkle in `project.yml`
  (`SPARKLE_ENABLED`), nested Sparkle signing in `build.sh`, tests in `UpdateServiceTests`.
  NOT yet build/test-verified; `SUPublicEDKey` still a placeholder (key generation pending).
- **Phase 2 (pipeline): scaffolding written** — `.github/workflows/release.yml`,
  `docs/release-process.md`. EdDSA keypair not yet generated; first release not yet cut.
- **Phase 4 (was ist neu): partly covered** — release-notes flow documented; gentle-reminder
  badge shipped with Phase 1; post-update "Was ist neu" panel still open.
- **Phase 5 (`rede` spin-off): prepared** — full brand-string inventory (92 classified hits),
  icon generator + rede README staged under `/tmp/rede-staging/`, licenses surface
  (`LicensesSection`) already in the fork. Repo clone/rebrand pending.
- **Phase 3 / 6: open** — gated on the Apple Developer account / MAS decision.
  `docs/app-store-runbook.md` documents every account-dependent step.

## Requirements Restatement

- rede should check for updates **automatically once per day** and on **manual request**.
- The end state is a **full auto-installer**: download, verify, install, relaunch — Sparkle-class UX.
- The update source is the fork **`aslomon/rede`** (not upstream `cmagnussen/blitztext-app`).
- The fork stays alive and publicly visible under the rede name — it is the feature base and
  matters for another project of the owner. The public product is a **separate app named `rede`**
  (lowercase wordmark; the German word for speech): own repo, branding, and bundle identity,
  distributed directly and optionally via the **Mac App Store** later. Features land in the fork
  first, then flow into `rede`.
- Users should **see progress**: release notes / "Was ist neu" surfaced in the app when an update
  arrives and after installing one.
- Privacy honesty is non-negotiable: the update check is a new outbound connection and must be
  documented; no telemetry, no system profiling.

## Current State (verified in repo)

- Version lives in `RedeMac/project.yml` (`MARKETING_VERSION 1.5`, `CURRENT_PROJECT_VERSION 15`)
  → `Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`). Not shown anywhere in the UI yet.
- No releases exist yet on either remote; the app is built locally via `build.sh`.
- Signing is local-stable ("rede Local Dev" cert) or ad-hoc. No Developer ID, no notarization.
  `build.sh` documents that a notarized release needs Developer ID + the
  `com.apple.security.cs.disable-library-validation` entitlement on the bundled `llama-server` helper.
- The app is **unsandboxed** (`com.apple.security.app-sandbox: false`) and a **menu bar accessory app**
  (`LSUIElement = true` in `Resources/Info.plist`).
- `redeInstallLocationService` already implements bundle replacement + relaunch primitives.
- `LaunchAtLoginService` is the established pattern for small `@Observable @MainActor` system services.
- Settings persist via `AppSettings` (Codable, `decodeIfPresent` migrations, tests in
  `AppSettingsCodableTests`).
- Legal: **MIT license** permits redistribution, modification, and selling. **`TRADEMARKS.md` requires
  a published fork to use its own name, icon, and branding.** Public distribution must not carry the
  rede brand — hence the `rede` spin-off (Phase 5).
- Identity-sensitive identifiers: bundle ID `app.rede.mac`, Keychain service
  `app.rede.preview.credentials` (`KeychainService`), data dir `Application Support/rede/`
  (`AppSupportPaths`), product name `rede`, dev cert CN "rede Local Dev".
- Hotkeys use `NSEvent` global monitors (`flagsChanged`) plus a CGEventTap that rides Accessibility
  trust; paste synthesis uses the same trust. Relevant for the Mac App Store feasibility assessment.

## Decisions

- **D1 — Use Sparkle 2.x via Swift Package Manager.** A hand-rolled downloader/installer is exactly
  the kind of security-critical code not to write yourself. Sparkle provides EdDSA-signed updates,
  atomic install + relaunch, delta updates, a scheduler, and "gentle reminders" for `LSUIElement`
  apps. The app is unsandboxed, which keeps the integration simple (no XPC sandbox dance).
- **D2 — GitHub Releases on the fork are the source of truth.** Tag = version. Update zips are
  release assets. The `appcast.xml` is published via GitHub Pages from a dedicated branch
  (`gh-pages`) so it never creates merge noise against upstream:
  `https://aslomon.github.io/rede/appcast.xml`.
- **D3 — Sparkle is hidden behind an `UpdateService` abstraction** (pattern: `LaunchAtLoginService`)
  and compiled behind a `SPARKLE_ENABLED` Swift compilation condition. Reason: the Mac App Store
  forbids self-updating apps, so a future MAS target must compile Sparkle out entirely. Views and
  `AppState` only ever talk to `UpdateService`.
- **D4 — Sparkle owns updater preferences.** `automaticallyChecksForUpdates`, last check date, and
  skipped versions live in Sparkle's own UserDefaults keys. They are **not** mirrored into
  `AppSettings` — one source of truth, no Codable migration. (Deliberate exception to the usual
  "everything in settings.json" pattern, because the framework owns this state.)
- **D5 — Daily automatic checks default ON**, via Info.plist (`SUEnableAutomaticChecks` = YES,
  `SUScheduledCheckInterval` = 86400), with an off-switch in settings and explicit copy in
  `docs/privacy.md`. `SUEnableSystemProfiling` is never set (no profile data leaves the Mac).
  `SUVerifyUpdateBeforeExtraction` = YES (strict verification before unarchiving).
- **D6 — The public product is a spin-off app `rede`, not an in-place rebrand of the fork.**
  The fork keeps the rede name for development and personal builds; marketed binaries must not
  use the rede brand (`TRADEMARKS.md`). `rede` derives from the fork (the fork stays a git
  remote; branding lives in a thin layer so merges stay cheap) and ships MIT attribution to the
  "Blitztext contributors". A fresh app identity means **no end-user migrations at all** — only the
  developer's own machines optionally import their rede data once.
- **D7 — Direct distribution (Developer ID + notarization + Sparkle) is the primary channel.**
  The Mac App Store is an optional later variant with documented feature compromises (Phase 6).

## Target Architecture

### App side

- `Services/UpdateService.swift` — `@Observable @MainActor final class`, guarded by
  `#if SPARKLE_ENABLED`. Wraps `SPUStandardUpdaterController(startingUpdater:updaterDelegate:userDriverDelegate:)`.
  Exposes:
  - `checkForUpdates()` (user-initiated, shows Sparkle UI)
  - `automaticallyChecksForUpdates: Bool` (read/write passthrough for the settings toggle)
  - `canCheckForUpdates`, `lastUpdateCheckDate`
  - `updateAvailable: Bool` + version string, driven via `SPUStandardUserDriverDelegate`
    gentle-reminder callbacks (menu bar apps must not steal focus with alerts)
  - German `helperText` / `errorText` copy, like `LaunchAtLoginService`
- `AppState` instantiates and holds `UpdateService` (orchestration only, no logic in views).
- `Resources/Info.plist` gains: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`,
  `SUScheduledCheckInterval` (86400), `SUVerifyUpdateBeforeExtraction`.
- `SystemSettingsView` gains an **"Updates" section** (between "Einrichtung" and "Sauber Entfernen"):
  current version + build (from `Bundle.main`), "zuletzt geprüft", button "Jetzt nach Updates
  suchen", toggle "Automatisch täglich prüfen", status/error line. Reuses `SectionLabel`,
  `PopoverActionButtonStyle`, existing typography. No new visual language → no `DESIGN.md` change.
- `MenuBarView` gains a secondary entry point ("Nach Updates suchen…") and a subtle
  "Update verfügbar" indication when a gentle reminder is pending.

### Distribution side

- Versioning rule: `CURRENT_PROJECT_VERSION` is a strictly monotonically increasing integer
  (Sparkle compares `sparkle:version`); `MARKETING_VERSION` is the user-facing string; git tag is
  `v$(MARKETING_VERSION)`.
- Release flow (automated in CI, with a documented local fallback):
  1. Build `llama-server` helper (`scripts/build-llamacpp-helper.sh`).
  2. `./build.sh --release --llamacpp-helper=… --llamacpp-helper-sha256=…` (universal).
  3. Sign with the stable identity (Developer ID once Phase 3 lands; until then local cert).
  4. Notarize + staple (Phase 3).
  5. `ditto -c -k --sequesterRsrc --keepParent rede.app rede-<version>.zip`.
  6. `sign_update` → `sparkle:edSignature` + `length`.
  7. Create GitHub release on the fork with the zip as asset; update `appcast.xml` on `gh-pages`
     (enclosure URLs point at the release assets; German release notes from the CHANGELOG).
- `build.sh` change: the standalone re-sign must sign nested Sparkle code in the right order
  (XPC services → `Autoupdate` / `Updater.app` → `Sparkle.framework` → app bundle), keeping the
  existing stable-identity/ad-hoc fallback logic.

## Phases

### Phase 1 — In-app updater (Sparkle integration)

All app-side work. Immediately testable against a local appcast served from `python3 -m http.server`,
with the existing local dev cert.

| #   | Task                                                                                                                                              |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.1 | `project.yml`: add Sparkle SPM package (pinned exact version), link to app target, add `SPARKLE_ENABLED` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` |
| 1.2 | `Services/UpdateService.swift` incl. gentle-reminder user-driver delegate                                                                         |
| 1.3 | `Resources/Info.plist`: SU keys (feed URL, public key placeholder, daily interval, strict verification)                                           |
| 1.4 | `SystemSettingsView`: "Updates" section (version, last check, manual check, daily toggle)                                                         |
| 1.5 | `MenuBarView`: manual entry point + update-available hint                                                                                         |
| 1.6 | `AppState`: own the service; verify `llama-server` child process terminates cleanly on update-relaunch                                            |
| 1.7 | `build.sh`: nested Sparkle signing                                                                                                                |
| 1.8 | Privacy: update `docs/privacy.md` + README ("what the daily check sends, and what it never sends")                                                |
| 1.9 | Tests: plist key presence, `UpdateService` pure display helpers (last-check formatting, state mapping)                                            |

Acceptance: `./test.sh` and `./build.sh --debug` pass; a fake `99.0` release in a local appcast
installs end-to-end on the dev machine and the app relaunches; disabling the toggle stops scheduled
checks (verified via Sparkle log); popover shows the update hint without stealing focus.

### Phase 2 — Release pipeline on the fork

| #   | Task                                                                                                                                 |
| --- | ------------------------------------------------------------------------------------------------------------------------------------ |
| 2.1 | Generate EdDSA keypair (`generate_keys`). Private key: local Keychain + CI secret only. **Never committed.** Public key → Info.plist |
| 2.2 | GitHub Actions `release.yml` on tag push `v*`: helper build → app build → sign → zip → `sign_update` → draft release with assets     |
| 2.3 | `gh-pages` branch + GitHub Pages serving `appcast.xml`; CI job patches and pushes it                                                 |
| 2.4 | `docs/release-process.md`: full runbook incl. local no-CI fallback and key backup/rotation notes                                     |
| 2.5 | Release-notes flow: CHANGELOG section per release → German HTML notes referenced via `sparkle:releaseNotesLink`                      |

Acceptance: pushing a test tag produces a draft release with a signed zip and an updated appcast; an
installed previous version detects, downloads, verifies, and installs it.

Interim caveat (until Phase 3): CI cannot hold the local dev cert, so CI artifacts would be ad-hoc
signed — that breaks TCC grants on every update and triggers Gatekeeper friction. Until Developer ID
exists, releases are built locally with the stable dev cert and are suitable for personal machines
only.

### Phase 3 — Developer ID & notarization (prerequisite for public distribution)

| #   | Task                                                                                                                                                                         |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 3.1 | Apple Developer Program membership; create "Developer ID Application" certificate                                                                                            |
| 3.2 | `build.sh` release path: Developer ID signing; helper gets hardened runtime + `com.apple.security.cs.disable-library-validation`; Sparkle components hardened                |
| 3.3 | `notarytool submit` + `stapler staple` in the release flow; CI secrets for the App Store Connect API key                                                                     |
| 3.4 | Verify: `spctl -a -t exec -vv` accepts; clean first install on a fresh Mac; Accessibility grant survives an update cycle (same Developer ID = stable designated requirement) |

Why this matters beyond Gatekeeper: a **stable signing identity is what keeps TCC (Accessibility)
grants alive across auto-updates** for end users. Without it, every update would silently break
paste until the user re-grants.

### Phase 4 — Show progress to users ("Was ist neu")

| #   | Task                                                                                                                      |
| --- | ------------------------------------------------------------------------------------------------------------------------- |
| 4.1 | German release notes rendered in Sparkle's update dialog (from the appcast)                                               |
| 4.2 | Optional: one-time "Was ist neu in <version>" panel on first launch after an update, fed from a bundled changelog excerpt |
| 4.3 | Menu-bar gentle reminder polish: subtle badge/dot in the popover instead of alerts                                        |

Acceptance: the update dialog shows readable German notes; the what's-new panel appears exactly once
per version; nothing steals focus while dictating.

### Phase 5 — Spin off `rede` as its own app (required before public release)

MIT permits reuse including commercial distribution, regardless of how much of the code changed. The
only obligations: keep the MIT license text + "Blitztext contributors" copyright notice in
distributed copies (an in-app acknowledgements surface is the standard way), and do not use the
rede name/icon/branding (`TRADEMARKS.md`). `rede` starts as a fresh app identity, so end users
never migrate anything.

| #   | Task                                                                                                                                                                                                                                                 |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 5.1 | Brand pass for `rede` (lowercase wordmark): icon, logo, visual identity, own `DESIGN.md`. Verify availability first: App Store name, domain, quick DPMA/EUIPO trademark search ("rede" is also the Portuguese word for "network" — check collisions) |
| 5.2 | New repo derived from the fork; sync strategy: fork remains a git remote, features land in the fork first, branding concentrated in `project.yml` + a small constants layer so merges stay cheap                                                     |
| 5.3 | New bundle ID + product name + dev cert CN / Developer ID; own appcast feed and product URLs                                                                                                                                                         |
| 5.4 | License compliance surface in-app (About/acknowledgements): MIT notices for Blitztext contributors, WhisperKit, llama.cpp, Sparkle; license metadata for downloaded GGUF/CoreML models                                                               |
| 5.5 | Optional one-shot importer for the developer's own machines (settings.json, Keychain key, downloaded models). End users start fresh; TCC is granted fresh for the new bundle ID anyway                                                               |
| 5.6 | German UI copy sweep where "rede" appears as product name; README/landing for `rede`                                                                                                                                                            |

### Phase 6 — `rede` on the Mac App Store (exploratory, decide after 1–5)

Hard constraints: App Sandbox is mandatory; self-updating apps are rejected → the MAS target
compiles with `SPARKLE_ENABLED` off (updates then come from the store — D3 makes this a build-flag
flip, not a rewrite).

Feasibility audit checklist (current code status → expected sandbox outcome):

- Microphone: entitlement already present → fine.
- Network client (OpenAI, Hugging Face downloads): fine.
- `llama-server` subprocess: needs child sandbox inheritance (`com.apple.security.inherit`) and a
  localhost server entitlement; signing rework required → medium effort, feasible.
- Global hotkeys: `flagsChanged` NSEvent monitors are sandbox-tolerant; the Escape CGEventTap rides
  Accessibility trust → see next point.
- Auto-paste (synthetic Cmd+V) + AX readers (`SelectionContextService`, `PasteContextAXReader`):
  user-granted Accessibility in a sandboxed MAS app has shipped precedents (window managers,
  clipboard tools that paste), but it is a **real App Review risk**. Mitigation: the copy-only
  fallback already exists — an honest MAS story can be "copies result to clipboard; auto-paste is a
  direct-download feature" if review forces it.
- Bring-your-own OpenAI key: shipped precedents exist; minor review risk.
- Model downloads into the app container: fine.

Verdict to revisit later: MAS is possible with feature compromises; direct distribution stays primary.

## Privacy Commitments

- The daily/manual check contacts only the appcast host and GitHub release assets over HTTPS.
- Transmitted: standard HTTP metadata (user agent including app version). Not transmitted: system
  profile, identifiers, usage data. `SUEnableSystemProfiling` is never enabled.
- `docs/privacy.md`, README, and the settings copy state this explicitly (Phase 1.8).
- The off-switch fully disables scheduled checks; manual checks remain available.

## Risks & Mitigations

- **Unstable signing breaks TCC on every update** → stable identity is mandatory for distributed
  updates (Phase 3); interim releases stay personal-use.
- **Nested Sparkle signing in the custom `build.sh` flow** is fiddly → explicit sign order, keep
  `codesign --verify --deep --strict`, and a manual end-to-end update test per release-process doc.
- **EdDSA private key loss** would strand users on old versions → documented key backup; Developer
  ID–signed archives are Sparkle's sanctioned fallback channel.
- **Drift between fork and `rede` repo** → features land in the fork first, branding layer (5.2),
  regular merges into `rede`.
- **Focus-stealing update UI in an `LSUIElement` app** → gentle reminders delegate from day one.
- **`llama-server` running during install/relaunch** → verify clean child termination on quit (1.6).

## Open Questions

1. Apple Developer Account: already available, or when? (Gates Phase 3; everything else can proceed.)
2. Name availability for `rede` (App Store name, domain, DPMA/EUIPO quick check) — the name itself
   is decided.
3. Default-ON daily checks vs. Sparkle's standard opt-in prompt on second launch — plan assumes
   default-ON with documented privacy copy and an off-switch (per explicit product request).
4. Eventual pricing model for `rede` (free / paid / freemium) — only affects the Phase 6 MAS decision.

## Suggested Execution Order

1. **Phase 1** now — pure app code, verifiable today against a local appcast.
2. **Phase 2** next — pipeline on the fork, personal-use releases.
3. **Phase 3 + 5 together, before anything public** — notarization and the `rede` spin-off are both
   public-release gates; `rede` launches notarized from day one.
4. **Phase 4** polish in between or after.
5. **Phase 6** is a separate go/no-go decision once 1–5 have shipped.
