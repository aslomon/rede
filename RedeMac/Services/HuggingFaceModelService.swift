import Foundation

/// Fetches GGUF chat models live from trusted Hugging Face orgs so the catalog expands automatically
/// as new models are published. Metadata that isn't in the API (parameter size, RAM fit) is parsed
/// heuristically from the file/repo name — good enough for the hardware fit, never load-bearing.
struct HuggingFaceModelService: Sendable {
  /// Trusted orgs whose GGUFs we surface. ggml-org is the official llama.cpp conversion org, so its
  /// files carry correct chat templates and pooling metadata.
  static let trustedAuthors = ["ggml-org"]

  let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  // MARK: - API DTOs

  private struct RepoSummary: Decodable {
    let id: String
  }

  private struct TreeEntry: Decodable {
    struct LFS: Decodable {
      let oid: String
      let size: Int64
    }
    let path: String
    let lfs: LFS?
  }

  // MARK: - Fetch

  /// Top chat GGUFs (Q4_K_M) across the trusted orgs, sorted by quality. Network failures yield [].
  func fetchChatModels(perAuthorLimit: Int = 16) async -> [LlamaCppModelCatalog.Model] {
    var repos: [String] = []
    for author in Self.trustedAuthors {
      repos += await listRepos(author: author, limit: perAuthorLimit)
    }

    let fetched = await withTaskGroup(of: LlamaCppModelCatalog.Model?.self) { group in
      for repo in repos {
        group.addTask { await self.model(forRepo: repo) }
      }
      var result: [LlamaCppModelCatalog.Model] = []
      for await model in group {
        if let model { result.append(model) }
      }
      return result
    }

    return Self.deduped(fetched).sorted { $0.qualityRank > $1.qualityRank }
  }

  private func listRepos(author: String, limit: Int) async -> [String] {
    guard
      let url = URL(
        string:
          "https://huggingface.co/api/models?author=\(author)&filter=gguf&sort=downloads&direction=-1&limit=\(limit)"
      ),
      let (data, _) = try? await session.data(from: url),
      let summaries = try? JSONDecoder().decode([RepoSummary].self, from: data)
    else { return [] }
    return summaries.map(\.id)
  }

  /// Repo-name fragments that mark non-chat or junk artifacts we never want to surface.
  static let excludedFragments = [
    "embed", "vlm", "test-model", "stories", "models-moved", "whisper", "audio", "-tts", "reranker",
    "infill", "-qat",
  ]

  private func model(forRepo repo: String) async -> LlamaCppModelCatalog.Model? {
    let lowerRepo = repo.lowercased()
    guard !Self.excludedFragments.contains(where: lowerRepo.contains) else { return nil }
    guard let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main"),
      let (data, _) = try? await session.data(from: url),
      let files = try? JSONDecoder().decode([TreeEntry].self, from: data)
    else { return nil }

    // A single-file Q4_K_M GGUF only — skip sharded ("00001-of-0000x") and non-chat artifacts.
    guard
      let file = files.first(where: { entry in
        let name = entry.path.lowercased()
        return name.hasSuffix(".gguf") && name.contains("q4_k_m") && !name.contains("-of-")
          && entry.lfs != nil
      }),
      let lfs = file.lfs
    else { return nil }

    return Self.makeModel(repo: repo, fileName: file.path, sha256: lfs.oid, sizeBytes: lfs.size)
  }

  // MARK: - Mapping

  static func makeModel(repo: String, fileName: String, sha256: String, sizeBytes: Int64)
    -> LlamaCppModelCatalog.Model
  {
    let author = repo.split(separator: "/").first.map(String.init) ?? ""
    let name = repo.split(separator: "/").last.map(String.init) ?? fileName
    let params = paramCount(from: fileName) ?? paramCount(from: repo)
    let gb = Double(sizeBytes) / 1_000_000_000.0
    let slug = repo.lowercased().replacingOccurrences(
      of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    return LlamaCppModelCatalog.Model(
      id: "hf-\(slug)",
      displayName: name.replacingOccurrences(of: "-GGUF", with: "").replacingOccurrences(
        of: "-gguf", with: ""),
      fileName: fileName,
      downloadURL: URL(
        string: "https://huggingface.co/\(repo)/resolve/main/\(fileName)?download=true")!,
      sha256: sha256,
      sizeBytes: sizeBytes,
      // Weights + KV cache + runtime overhead.
      estimatedRuntimeRAMGB: gb + 2.5,
      parameterSize: params.map { Self.formatParams($0) } ?? "—",
      quantization: "Q4_K_M",
      licenseName: "—",
      licenseURL: URL(string: "https://huggingface.co/\(repo)"),
      blurb: "Live aus dem Hugging-Face-Katalog (\(author)).",
      qualityRank: params.map { Int($0 * 2) } ?? 1
    )
  }

  /// Drops anything already shipped in the curated catalog (same file name), so curated entries with
  /// honest RAM estimates win over the heuristic ones.
  static func deduped(_ models: [LlamaCppModelCatalog.Model]) -> [LlamaCppModelCatalog.Model] {
    let curatedFiles = Set(
      (LlamaCppModelCatalog.models + LlamaCppModelCatalog.embeddingModels).map(\.fileName))
    var seen = Set<String>()
    return models.filter { model in
      guard !curatedFiles.contains(model.fileName) else { return false }
      return seen.insert(model.fileName).inserted
    }
  }

  /// Billions of parameters parsed from a name like "Qwen3-14B-Q4_K_M" → 14.0, or "0.6B" → 0.6.
  static func paramCount(from text: String) -> Double? {
    guard
      let match = text.range(
        of: "([0-9]+(\\.[0-9]+)?)\\s*[bB]\\b", options: .regularExpression)
    else { return nil }
    let token = text[match].lowercased().replacingOccurrences(of: "b", with: "")
      .trimmingCharacters(in: .whitespaces)
    return Double(token)
  }

  static func formatParams(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))B" : "\(value)B"
  }
}
