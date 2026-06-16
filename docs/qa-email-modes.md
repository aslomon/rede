# QA Checklist: Modes, Hotkeys, Email Memory, Variants

Use this checklist before shipping changes that touch dynamic modes, shortcut handling, semantic
email memory, or the recording pill.

## Dynamic Modes

- Create an E-Mail mode copy, rename it, change prompt/context/model settings, close settings, and
  reopen the app. The mode name, order, and settings persist.
- Move the custom mode up/down in Prompts settings. The menu bar order follows the settings order.
- Delete the custom mode. Its hotkey disappears and the fixed default mode remains available.
- Reset a fixed mode. It returns to defaults but is not deleted.
- Run a custom mode and confirm the archive row shows the custom mode name, not only the base slot.

## Hotkeys

- Assign a unique shortcut to a custom mode. Hold/toggle behavior starts and stops that mode.
- Assign the same shortcut to two enabled modes. Both affected mode cards and System settings show
  a conflict warning.
- Disable a shortcut. The mode remains usable from the menu, but the global shortcut no longer
  starts it.
- Restart rede and confirm shortcut labels and behavior survive settings reload.

## Semantic Email Memory

- With Archive off, confirm per-mode semantic email controls are disabled with a clear hint.
- Enable Archive and global semantic email memory. Run an E-Mail rewrite into a normal text field.
  A semantic memory record is stored locally.
- Run the next E-Mail rewrite with `Wenig`, `Mittel`, and `Viel`; verify retrieval budgets change
  in tests/logged prompt diagnostics without adding unconfirmed facts.
- Run into a secure/password field. The result pastes, but no archive or semantic memory record is
  created.
- Clear semantic email memory from Models settings and verify the store is empty.

## Two-Variant Pill

- Enable `Immer zwei Versionen zeigen` for Text verbessern, Dampf ablassen, and Emoji/Social.
  Each mode should pause in the pill and show two choices after rewriting.
- Click `Einfügen` on version 2. Only that version is pasted and archived.
- Click `Kopieren` on a version. The text is copied and the active run is dismissed without paste.
- Dismiss the variants card. The workflow resets without archive or paste.
- Simulate a second-variant failure. The first rewrite falls back to the normal one-result paste
  path.
