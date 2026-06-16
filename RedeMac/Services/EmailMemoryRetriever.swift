import Foundation

struct EmailMemoryMatch: Sendable, Equatable {
  let record: EmailSemanticMemoryRecord
  let score: Double
}

struct EmailSemanticMemoryContext: Sendable, Equatable {
  let matches: [EmailMemoryMatch]
  let level: SemanticEmailEnrichmentLevel

  var isEmpty: Bool { matches.isEmpty }
}

typealias EmailMemoryMatchLoader = @Sendable (String) async -> [EmailMemoryMatch]

enum EmailMemoryRetriever {
  static func retrieve(
    queryEmbedding: [Double],
    records: [EmailSemanticMemoryRecord],
    limit: Int,
    minScore: Double
  ) -> [EmailMemoryMatch] {
    guard limit > 0 else { return [] }
    return records
      .map { record in
        EmailMemoryMatch(
          record: record,
          score: cosineSimilarity(queryEmbedding, record.embedding)
        )
      }
      .filter { $0.score >= minScore }
      .sorted { lhs, rhs in
        if lhs.score == rhs.score { return lhs.record.date > rhs.record.date }
        return lhs.score > rhs.score
      }
      .prefix(limit)
      .map { $0 }
  }

  static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
    var dot = 0.0
    var lhsNorm = 0.0
    var rhsNorm = 0.0

    for index in lhs.indices {
      dot += lhs[index] * rhs[index]
      lhsNorm += lhs[index] * lhs[index]
      rhsNorm += rhs[index] * rhs[index]
    }

    guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
    return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
  }
}
