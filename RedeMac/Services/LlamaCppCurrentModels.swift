import Foundation

extension LlamaCppModelCatalog {
  /// Publisher metadata verified on 2026-10-19. Revision URLs and checksums refer to the same
  /// immutable artifacts. RAM values are conservative estimates; neutral ranks preserve existing
  /// recommendations until these models have been benchmarked for rewriting on supported Macs.
  static let currentModels: [Model] = [
    Model(
      id: "qwen3.5-4b-q4-k-m",
      displayName: "Qwen3.5 · 4B · Q4_K_M",
      fileName: "Qwen3.5-4B-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/"
          + "resolve/e87f176479d0855a907a41277aca2f8ee7a09523/"
          + "Qwen3.5-4B-Q4_K_M.gguf?download=true"
      )!,
      sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
      sizeBytes: 2_740_937_888,
      estimatedRuntimeRAMGB: 5.5,
      parameterSize: "4B",
      quantization: "Q4_K_M",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-4B"),
      blurb: "Kompaktes Qwen3.5-Modell für lokale Umschreibungen.",
      qualityRank: 0
    ),
    Model(
      id: "qwen3.5-9b-q4-k-m",
      displayName: "Qwen3.5 · 9B · Q4_K_M",
      fileName: "Qwen3.5-9B-Q4_K_M.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/"
          + "resolve/3885219b6810b007914f3a7950a8d1b469d598a5/"
          + "Qwen3.5-9B-Q4_K_M.gguf?download=true"
      )!,
      sha256: "03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8",
      sizeBytes: 5_680_522_464,
      estimatedRuntimeRAMGB: 9.0,
      parameterSize: "9B",
      quantization: "Q4_K_M",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-9B"),
      blurb: "Qwen3.5 für lokale Umschreibungen auf Macs mit mehr RAM.",
      qualityRank: 0
    ),
    Model(
      id: "gemma-4-e2b-it-q4-0",
      displayName: "Gemma 4 · E2B · Q4_0",
      fileName: "gemma-4-E2B-it-Q4_0.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/"
          + "resolve/b4243c156154b6dca9324415f8c7ccc098b4aed1/"
          + "gemma-4-E2B-it-Q4_0.gguf?download=true"
      )!,
      sha256: "8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52",
      sizeBytes: 2_841_481_184,
      estimatedRuntimeRAMGB: 5.5,
      parameterSize: "E2B",
      quantization: "Q4_0",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/google/gemma-4-E2B-it"),
      blurb: "Googles Gemma 4 in kompakt für lokale Umschreibungen.",
      qualityRank: 0
    ),
    Model(
      id: "gemma-4-e4b-it-q4-0",
      displayName: "Gemma 4 · E4B · Q4_0",
      fileName: "gemma-4-E4B-it-Q4_0.gguf",
      downloadURL: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/"
          + "resolve/b8093469224f83f5c38f691eb906c380e9e63114/"
          + "gemma-4-E4B-it-Q4_0.gguf?download=true"
      )!,
      sha256: "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2",
      sizeBytes: 4_590_807_392,
      estimatedRuntimeRAMGB: 8.0,
      parameterSize: "E4B",
      quantization: "Q4_0",
      licenseName: "Apache-2.0",
      licenseURL: URL(string: "https://huggingface.co/google/gemma-4-E4B-it"),
      blurb: "Googles Gemma 4 für lokale Umschreibungen auf Macs mit mehr RAM.",
      qualityRank: 0
    )
  ]
}
