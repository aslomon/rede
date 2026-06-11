import SwiftUI

// MARK: - Über & Lizenzen (System tab)

/// Open-source attribution surface. The MIT license requires shipping the copyright notice with
/// every distributed copy — this section satisfies that for the app itself and its bundled
/// dependencies. License texts stay in their original English; the framing copy is German.
struct LicensesSection: View {
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "über & lizenzen", icon: "info.circle")

      Text(
        "diese app baut auf open-source-software auf. die lizenzhinweise gehören zu jeder "
          + "weitergegebenen kopie dazu."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      DisclosureGroup(isExpanded: $expanded) {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Self.notices) { notice in
            VStack(alignment: .leading, spacing: 2) {
              Text(notice.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
              Text(notice.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
          }

          Text(Self.mitLicenseText)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.top, 2)
        }
        .padding(.top, 6)
      } label: {
        Text("open-source-lizenzen anzeigen")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Notice data

  struct Notice: Identifiable {
    let name: String
    let detail: String
    var id: String { name }
  }

  static let notices: [Notice] = [
    Notice(
      name: "rede",
      detail: "Copyright (c) 2026 rede contributors — MIT License. "
        + "Diese App basiert auf dem Open-Source-Projekt rede."
    ),
    Notice(
      name: "WhisperKit / Argmax OSS",
      detail: "Copyright (c) Argmax, Inc. — MIT License. Lokale Transkription (CoreML)."
    ),
    Notice(
      name: "llama.cpp",
      detail: "Copyright (c) 2023–2026 The ggml authors — MIT License. "
        + "Lokales Sprachmodell-Runtime (gebündelter llama-server)."
    ),
    Notice(
      name: "Sparkle",
      detail: "Copyright (c) Sparkle Project contributors — MIT License. In-App-Updates."
    ),
    Notice(
      name: "Modelle",
      detail: "Heruntergeladene Sprach- und Transkriptionsmodelle (GGUF/CoreML) haben eigene "
        + "Lizenzen des jeweiligen Anbieters; sie werden beim Download angezeigt bzw. verlinkt."
    ),
  ]

  /// The canonical MIT license body shipped once (it is identical for all MIT notices above).
  static let mitLicenseText = """
    MIT License: Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal in the \
    Software without restriction, including without limitation the rights to use, copy, \
    modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and \
    to permit persons to whom the Software is furnished to do so, subject to the following \
    conditions: The above copyright notice and this permission notice shall be included in \
    all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", \
    WITHOUT WARRANTY OF ANY KIND.
    """
}
