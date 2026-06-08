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
      blurb: "Schnelles Standardmodell für lokale Umschreibungen auf kleinen und mittleren Macs."
    )
  ]

  static func model(for id: String) -> Model? {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    return models.first { $0.id == trimmed }
  }
}
