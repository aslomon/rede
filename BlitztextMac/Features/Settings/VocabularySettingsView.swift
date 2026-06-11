import SwiftUI

// MARK: - Vocabulary settings (Tab: Vokabular)

/// ONE page for everything word-related, grouped by INTENT instead of being scattered across the
/// Modelle and Archiv tabs as three overlapping mechanisms:
///  1. "Memory" — master toggle + status = primary concern; sits at the top.
///  2. "Eigene Identität" — foundational, short.
///  3. "Begriffe" — known words Whisper should hear + spell correctly. Merges old Eigennamen
///     (manual) and auto-learned Memory terms into ONE list; functionally identical.
///  4. "Diktier-Wörterbuch" — say A → write B, plus spoken punctuation.
/// The underlying stores and the term-injection pipeline are unchanged; this only unifies the UI.
struct VocabularySettingsView: View {
  @Bindable var appState: AppState

  @State private var newTerm = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      memorySection
      identitySection
      recognizeSection
    }
    .padding(16)
    .task {
      await appState.localModelManager.refresh()
    }
  }

  // MARK: - Suggestions nudge banner

  /// Tinted EmptyStateCard-style banner with badge count + CTA. Shown at the top of memorySection
  /// body (below master toggle) when there are pending improvement suggestions.
  @ViewBuilder
  private var improvementSuggestionsNudge: some View {
    let count = appState.improvementSuggestions.count
    if count > 0 {
      Button {
        NotificationCenter.default.post(name: .openArchiveWindow, object: nil)
      } label: {
        HStack(spacing: 8) {
          // Badge count — prominent
          Text("\(count)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.blue)
            .frame(minWidth: 20)
          VStack(alignment: .leading, spacing: 1) {
            Text(count == 1 ? "neuer lern-vorschlag" : "\(count) neue lern-vorschläge")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.primary)
            Text("im archiv ansehen →")
              .font(.system(size: 10.5))
              .foregroundStyle(.blue)
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Flat tint — nested inside the memory card, so no glass layer (DESIGN.md).
        .tintBanner(.blue)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        count == 1
          ? "1 neuer Lern-Vorschlag — Im Archiv ansehen"
          : "\(count) neue Lern-Vorschläge — Im Archiv ansehen"
      )
    }
  }

  private var identitySection: some View {
    SettingsSection(
      "eigene identität",
      icon: "person.crop.circle",
      caption: "dein name als feste schreibperspektive für E-Mail und umschreiben."
    ) {
      TextField("dein name", text: $appState.appSettings.userDisplayName)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))

      InfoDisclosure("wofür genau?") {
        Text(
          "wird lokal gespeichert, als schreibweise-hinweis genutzt und im E-Mail-Modus als \u{201E}Ich schreibe als \u{2026}\u{201C} mitgegeben."
        )
      }
    }
  }

  // MARK: - Recognize (merged manual + memory)

  private var recognizeSection: some View {
    SettingsSection(
      "begriffe",
      icon: "character.book.closed",
      caption:
        "exakte schreibweisen für namen, marken und fachwörter."
    ) {
      let terms = appState.recognizeTerms
      if terms.isEmpty {
        Text("noch keine begriffe — füge unten namen oder fachwörter hinzu.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        FlowLayout(spacing: 5) {
          ForEach(terms) { term in
            RecognizeChip(
              term: term,
              onRemove: {
                withAnimation(.easeOut(duration: 0.15)) { appState.removeRecognizeTerm(term) }
              }
            )
          }
        }
      }

      HStack(spacing: 6) {
        TextField("neuer begriff", text: $newTerm)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 11))
          .onSubmit { addTerm() }
        Button {
          addTerm()
        } label: {
          Image(systemName: "plus.circle.fill")
        }
        .buttonStyle(PopoverIconButtonStyle(.primary))
        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
      }

      fuzzyToggle

      Divider().opacity(0.4)

      // Replacements live here too — to the user they are the same idea as Begriffe.
      DictationReplacementsBlock(appState: appState)

      // Contextually relevant here — explains how Begriffe are used
      InfoDisclosure("wie begriffe genutzt werden") {
        VStack(alignment: .leading, spacing: 5) {
          Text(
            "beim diktieren werden sie als Whisper-Hinweis mitgegeben, damit ähnlich klingende wörter eher richtig erkannt werden."
          )
          Text(
            "beim umschreiben werden sie dem sprachmodell als schreibweisen-liste gegeben: wenn der begriff vorkommt, soll er exakt so geschrieben werden."
          )
          Text(
            "manuell hinzugefügte und automatisch gelernte begriffe landen in derselben sichtbaren liste."
          )
          Divider().opacity(0.4)
          Text(
            "memory: lernt aus deinem archiv. wiederkehrende eigen- und fachbegriffe werden automatisch normale begriffe; bei E-Mail kann memory zusätzlich ähnliche frühere antworten als lokalen hintergrund finden."
          )
          Text(
            "wenn ein automatisch gelernter begriff nicht passt, entfernst du ihn aus der begriffsliste. danach wird er nicht erneut gelernt."
          )
          Text(
            "ersetzungen: feste regeln wie gesagtes wort A → geschriebener text B. sie werden direkt auf den transkribierten text angewendet."
          )
        }
      }
    }
  }

  /// Conservative on-device fuzzy correction of the recognize terms above: snaps near-miss spellings
  /// back to the canonical word. Default ON; only fires on clear, unambiguous near-misses.
  private var fuzzyToggle: some View {
    VStack(alignment: .leading, spacing: 3) {
      Toggle(
        "begriffe automatisch korrigieren",
        isOn: $appState.appSettings.fuzzyCorrectionEnabled
      )
      .toggleStyle(.switch)
      .controlSize(.small)
      .font(.system(size: 11.5))

      Text(
        "korrigiert tippfehler-nahe schreibweisen deiner begriffe (z. B. \u{201E}Rinert\u{201C} \u{2192} \u{201E}Rinnert\u{201C})."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func addTerm() {
    let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    withAnimation(.easeOut(duration: 0.15)) { appState.addRecognizeTerm(trimmed) }
    newTerm = ""
  }

  // MARK: - Memory

  private var memorySection: some View {
    SettingsSection(
      "memory",
      icon: "brain",
      action: (
        label: "prüfen",
        perform: { Task { await appState.localModelManager.refresh() } }
      )
    ) {
      // 1. Master toggle + status pill
      HStack {
        Toggle("aktivieren", isOn: $appState.isUnifiedMemoryEnabled)
          .toggleStyle(.switch)
          .controlSize(.small)
        Spacer()
        BlitzStatusPill(state: memoryPillState, label: appState.unifiedMemoryStatusLabel)
      }

      if appState.isUnifiedMemoryEnabled {
        // 2. Suggestions nudge banner — top of expanded body, before InfoDisclosure
        improvementSuggestionsNudge

        // 3. "jetzt analysieren" directly below master toggle (primary action)
        HStack(spacing: 8) {
          if appState.isRecomputingMemory {
            ProgressView()
              .controlSize(.small)
          }
          Button {
            appState.recomputeMemory()
          } label: {
            Label("jetzt analysieren", systemImage: "sparkle.magnifyingglass")
          }
          .buttonStyle(PopoverActionButtonStyle(.primary))
          .disabled(appState.isRecomputingMemory || !appState.isArchiveEnabled)
        }

        // 4. InfoDisclosure — optional details
        InfoDisclosure("was memory macht") {
          VStack(alignment: .leading, spacing: 5) {
            Text(
              "vokabular-memory: sucht im archiv nach wiederkehrenden namen und fachbegriffen. namen/fremdwörter werden nach zwei vorkommen übernommen, fachbegriffe nach drei."
            )
            Text(
              "E-Mail-Memory: speichert fertige E-Mail-Antworten lokal mit embeddings und findet beim nächsten E-Mail-Modus ähnliche frühere antworten als hintergrund."
            )
            Text(
              "korrekturlernen: liest nach dem einfügen optional nochmal den feldinhalt, um deine manuellen korrekturen als vorschläge zu erkennen."
            )
            Text(
              "memory aus stoppt lernen und kontextsuche. bereits gelernte begriffe bleiben als vokabular aktiv."
            )
          }
        }

        emailMemoryStatusRow

        Toggle("aus korrekturen lernen", isOn: $appState.isImprovementDetectionEnabled)
          .toggleStyle(.switch)
          .controlSize(.small)

        // 5. Destructive buttons stacked vertically — reduces mis-tap risk
        clearMemoryControls
      }
    }
  }

  private var emailMemoryStatusRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("E-Mail-Memory")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        BlitzStatusPill(state: emailMemoryPillState, label: appState.semanticEmailMemoryStatusLabel)
        Spacer(minLength: 0)
      }

      HStack(spacing: 8) {
        Text("Embedding-Modell")
          .font(.system(size: 10.5))
          .foregroundStyle(.tertiary)
        Text(appState.selectedEmbeddingModelName)
          .font(.system(size: 11, design: .monospaced))
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
      }

      embeddingProgress

    }
  }

  @ViewBuilder
  private var embeddingProgress: some View {
    let modelID = appState.selectedEmbeddingModelName
    if let pull = appState.localModelManager.llamaCppDownloads[modelID] {
      VStack(alignment: .leading, spacing: 4) {
        ProgressView(value: pull.fraction)
        Text(pull.statusText)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
    } else if let error = appState.localModelManager.lastError,
      appState.appSettings.semanticEmailMemoryEnabled
    {
      Text(error)
        .font(.system(size: 10.5))
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var emailMemoryPillState: BlitzStatusPill.State {
    if !appState.appSettings.semanticEmailMemoryEnabled { return .muted }
    if appState.semanticEmailMemoryIsReady { return .ready }
    if appState.semanticEmailEmbeddingIsPreparing { return .download }
    return .warning
  }

  private var memoryPillState: BlitzStatusPill.State {
    if !appState.isUnifiedMemoryEnabled { return .muted }
    if appState.semanticEmailEmbeddingIsPreparing { return .download }
    if appState.appSettings.semanticEmailMemoryEnabled, !appState.semanticEmailEmbeddingIsReady {
      return .warning
    }
    return .ready
  }

  private var clearMemoryButton: some View {
    DestructiveClearButton(
      "memory löschen",
      message:
        "alle automatisch gelernten begriffe werden entfernt. das lässt sich nicht rückgängig machen."
    ) {
      appState.clearMemory()
    }
  }

  private var clearEmailMemoryButton: some View {
    DestructiveClearButton(
      "E-Mail-Memory löschen",
      message:
        "alle semantisch gespeicherten E-Mail-Texte werden entfernt. das lässt sich nicht rückgängig machen."
    ) {
      appState.clearEmailSemanticMemory()
    }
  }

  /// Two destructive buttons stacked vertically (6pt gap) instead of side-by-side HStack.
  /// Reduces mis-tap risk at 410pt popover width.
  private var clearMemoryControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      clearMemoryButton
      clearEmailMemoryButton
    }
  }
}

// MARK: - Chips

/// A recognize term in the merged list. Shows a small source glyph (person = manual,
/// wand.and.stars = learned from Memory) and a trailing ✕ that removes it from whichever
/// store owns it.
private struct RecognizeChip: View {
  let term: AppState.RecognizeTerm
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      // "sparkles" (purple) replaced by "wand.and.stars" (.secondary) — avoids collision
      // with the textImprover mode accent (purple per DESIGN.md). Manual chips stay .tertiary
      // so the two source types are distinguishable without colour.
      Image(systemName: term.fromMemory ? "wand.and.stars" : "person.fill")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(term.fromMemory ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        .help(term.fromMemory ? "aus dem archiv gelernt" : "manuell hinzugefügt")
      Text(term.text)
        .font(.system(size: 10.5))
        .foregroundStyle(.primary)
      // Replaced SubtleButtonStyle with .plain + .contentShape(Circle) for 18pt minimum tap area
      // without adding visual weight — keeps chip visually minimal.
      Button {
        onRemove()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 7, weight: .bold))
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .contentShape(Circle().scale(1.6))
      .help("entfernen")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    // ChipBackgroundModifier: thinMaterial on macOS 26+, MenuBarTokens fill on 14–25.
    // Per no-stacking rule: .thinMaterial (not .glassEffect) inside GroupBox.
    .modifier(ChipBackgroundModifier(accent: .blue))
  }
}
