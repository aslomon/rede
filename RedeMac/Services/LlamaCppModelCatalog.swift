import Foundation

enum LlamaCppModelCatalog {
  struct Model: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let downloadURL: URL
    let sha256: String
    let sizeBytes: Int64
    let estimatedRuntimeRAMGB: Double
    let parameterSize: String
    let quantization: String
    let licenseName: String
    let licenseURL: URL?
    let blurb: String
    /// Higher = better rewrite quality. Drives the hardware-aware recommendation among the models
    /// that fit this Mac. Embedding models use 0 (never ranked as a rewrite model).
    let qualityRank: Int

    var downloadGB: Double { Double(sizeBytes) / 1_000_000_000.0 }
  }

  static let models: [Model] = [
    Model(
      id: "qwen3-1.7b-q4-k-m",
      displayName: "Qwen3 · 1.7B · Q4_K_M",
      fileName: "Qwen3-1.7B-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true"
      )!,
      sha256: "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5",
      sizeBytes: 1_280_000_000,
      estimatedRuntimeRAMGB: 2.8,
      parameterSize: "1.7B",
      quantization: "Q4_K_M",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF"),
      blurb: "Schnell und sparsam — ideal für 8-GB-Macs.",
      qualityRank: 10
    ),
    Model(
      id: "gemma-3-4b-it-q4-k-m",
      displayName: "Gemma 3 · 4B · Q4_K_M",
      fileName: "gemma-3-4b-it-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf?download=true"
      )!,
      sha256: "882e8d2db44dc554fb0ea5077cb7e4bc49e7342a1f0da57901c0802ea21a0863",
      sizeBytes: 2_489_757_856,
      estimatedRuntimeRAMGB: 5.0,
      parameterSize: "4B",
      quantization: "Q4_K_M",
      licenseName: "Gemma",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF"),
      blurb: "Googles Gemma 3 in kompakt — gute Qualität für 8–16-GB-Macs.",
      qualityRank: 20
    ),
    Model(
      id: "qwen3-4b-q4-k-m",
      displayName: "Qwen3 · 4B · Q4_K_M",
      fileName: "Qwen3-4B-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true"
      )!,
      sha256: "ab27b9bfa375a178d6cba48f3ad892b94b7739659dcc7aae8058ce0ffed6b328",
      sizeBytes: 2_497_280_640,
      estimatedRuntimeRAMGB: 5.0,
      parameterSize: "4B",
      quantization: "Q4_K_M",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/Qwen3-4B-GGUF"),
      blurb: "Kräftiges Kompaktmodell für 16-GB-Macs.",
      qualityRank: 25
    ),
    Model(
      id: "qwen3-8b-q4-k-m",
      displayName: "Qwen3 · 8B · Q4_K_M",
      fileName: "Qwen3-8B-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true"
      )!,
      sha256: "a67d87633b5f5f191a5bd11e6d37cab18b9ce3d4a6af6861561e8a767352080b",
      sizeBytes: 5_027_783_872,
      estimatedRuntimeRAMGB: 8.0,
      parameterSize: "8B",
      quantization: "Q4_K_M",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/Qwen3-8B-GGUF"),
      blurb: "Ausgewogen für 16-GB-Macs — natürliche Umschreibungen.",
      qualityRank: 35
    ),
    Model(
      id: "gemma-3-12b-it-q4-k-m",
      displayName: "Gemma 3 · 12B · Q4_K_M",
      fileName: "gemma-3-12b-it-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-12b-it-GGUF/resolve/main/gemma-3-12b-it-Q4_K_M.gguf?download=true"
      )!,
      sha256: "7bb69bff3f48a7b642355d64a90e481182a7794707b3133890646b1efa778ff5",
      sizeBytes: 7_300_574_976,
      estimatedRuntimeRAMGB: 10.5,
      parameterSize: "12B",
      quantization: "Q4_K_M",
      licenseName: "Gemma",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/gemma-3-12b-it-GGUF"),
      blurb: "Googles Gemma 3 für 24-GB-Macs — sehr stark im Deutschen.",
      qualityRank: 50
    ),
    Model(
      id: "qwen3-14b-q4-k-m",
      displayName: "Qwen3 · 14B · Q4_K_M",
      fileName: "Qwen3-14B-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/Qwen3-14B-GGUF/resolve/main/Qwen3-14B-Q4_K_M.gguf?download=true"
      )!,
      sha256: "5ff1fe7a07aebc8d090682d01b17cf268a1b4680c6477050ce75a600aecb9efb",
      sizeBytes: 9_001_753_376,
      estimatedRuntimeRAMGB: 12.5,
      parameterSize: "14B",
      quantization: "Q4_K_M",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/Qwen3-14B-GGUF"),
      blurb: "Hohe Qualität für 24–32-GB-Macs.",
      qualityRank: 55
    ),
    Model(
      id: "gemma-3-27b-it-q4-k-m",
      displayName: "Gemma 3 · 27B · Q4_K_M",
      fileName: "gemma-3-27b-it-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-27b-it-GGUF/resolve/main/gemma-3-27b-it-Q4_K_M.gguf?download=true"
      )!,
      sha256: "edc9aff4d811a285b9157618130b08688b0768d94ee5355b02dc0cb713012e15",
      sizeBytes: 16_546_404_736,
      estimatedRuntimeRAMGB: 20.0,
      parameterSize: "27B",
      quantization: "Q4_K_M",
      licenseName: "Gemma",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/gemma-3-27b-it-GGUF"),
      blurb: "Großes Gemma-3-Modell für 32-GB-Macs+ — exzellente Texte.",
      qualityRank: 70
    ),
    Model(
      id: "qwen3-32b-q4-k-m",
      displayName: "Qwen3 · 32B · Q4_K_M",
      fileName: "Qwen3-32B-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/Qwen3-32B-GGUF/resolve/main/Qwen3-32B-Q4_K_M.gguf?download=true"
      )!,
      sha256: "4d7312a48e7f11572045afe2b27b3bc3407f3f01ceb9aedb594ea82364f91194",
      sizeBytes: 19_762_149_152,
      estimatedRuntimeRAMGB: 24.0,
      parameterSize: "32B",
      quantization: "Q4_K_M",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/ggml-org/Qwen3-32B-GGUF"),
      blurb: "Spitzenqualität für Macs mit viel RAM (48 GB+).",
      qualityRank: 80
    ),
  ]

  /// Embedding models — deliberately separate from chat `models` so they never surface in the
  /// rewrite picker. Powers semantic e-mail memory via a dedicated llama.cpp embedding server.
  static let embeddingModels: [Model] = [
    Model(
      id: "nomic-embed-text-v1.5-q8",
      displayName: "Nomic Embed Text v1.5 · Q8_0",
      fileName: "nomic-embed-text-v1.5.Q8_0.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q8_0.gguf?download=true"
      )!,
      sha256: "3e24342164b3d94991ba9692fdc0dd08e3fd7362e0aacc396a9a5c54a544c3b7",
      sizeBytes: 146_146_432,
      estimatedRuntimeRAMGB: 0.7,
      parameterSize: "137M",
      quantization: "Q8_0",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF"),
      blurb: "Lokales Embedding-Modell für das semantische E-Mail-Memory (768 Dimensionen).",
      qualityRank: 0
    )
  ]

  /// The default embedding model backing semantic e-mail memory.
  static var defaultEmbeddingModel: Model { embeddingModels[0] }

  /// Looks up any catalog model — chat or embedding — by id. Used by the runtime and store.
  static func model(for id: String) -> Model? {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    return (models + embeddingModels).first { $0.id == trimmed }
  }

  /// Looks up a chat/rewrite model only. Used to validate a stored rewrite selection so an
  /// embedding id can never be mistaken for a rewrite model.
  static func chatModel(for id: String) -> Model? {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    return models.first { $0.id == trimmed }
  }

  /// Builds a downloadable Model from a direct `.gguf` URL the user entered. No pinned checksum —
  /// the file's hash is recorded after download. Returns nil for anything that isn't a safe https
  /// link to a `.gguf` file.
  static func customModel(fromURLString urlString: String) -> Model? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
    else { return nil }
    let fileName = url.lastPathComponent
    guard fileName.hasSuffix(".gguf"), fileName.count > 5,
      !fileName.contains("/"), !fileName.contains("..")
    else { return nil }
    let base = String(fileName.dropLast(5))
    let slug = base.lowercased().replacingOccurrences(
      of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    return Model(
      id: "custom-\(slug)",
      displayName: base,
      fileName: fileName,
      downloadURL: url,
      sha256: "",
      sizeBytes: 0,
      estimatedRuntimeRAMGB: 0,
      parameterSize: "—",
      quantization: "—",
      licenseName: "—",
      licenseURL: nil,
      blurb: "Eigenes Modell von \(url.host ?? "URL").",
      qualityRank: 0
    )
  }

  /// A display model for an installed manifest: the rich catalog entry if the id is known, otherwise
  /// a descriptor derived from the manifest itself (custom / dynamically-added models).
  static func installedModel(from manifest: LlamaCppModelStore.VerifiedManifest) -> Model {
    if let known = model(for: manifest.modelID) { return known }
    let gb = Double(manifest.sizeBytes) / 1_000_000_000.0
    return Model(
      id: manifest.modelID,
      displayName: manifest.displayName ?? manifest.fileName,
      fileName: manifest.fileName,
      downloadURL: manifest.downloadURL.flatMap(URL.init(string:))
        ?? URL(string: "https://invalid.local")!,
      sha256: manifest.sha256,
      sizeBytes: manifest.sizeBytes,
      estimatedRuntimeRAMGB: gb + 2,
      parameterSize: manifest.parameterSize ?? "—",
      quantization: manifest.quantization ?? "—",
      licenseName: "—",
      licenseURL: nil,
      blurb: "Eigenes Modell.",
      qualityRank: 0
    )
  }
}
