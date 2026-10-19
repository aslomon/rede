import Foundation

struct LiveTranscriptAssembler {
    private struct Item {
        var sequence: Int
        var delta = ""
        var predecessor: String?
        var committed = false
        var final: String?
    }
    private var items: [String: Item] = [:]
    private var revision = 0
    var completedItemCount: Int { items.values.filter { $0.final != nil }.count }
    var isComplete: Bool { !items.isEmpty && items.values.allSatisfy { $0.committed && $0.final != nil } }

    var snapshot: LiveTranscriptSnapshot {
        var stable: [String] = [], provisional: [String] = []
        var prefixComplete = true
        for id in orderedIDs {
            guard let item = items[id] else { continue }
            let text = (item.final ?? item.delta).trimmingCharacters(in: .whitespacesAndNewlines)
            prefixComplete = prefixComplete && item.committed && item.final != nil
            if !text.isEmpty {
                if prefixComplete { stable.append(text) } else { provisional.append(text) }
            }
        }
        return LiveTranscriptSnapshot(stableText: stable.joined(separator: " "),
                                      provisionalText: provisional.joined(separator: " "), revision: revision)
    }

    mutating func delta(itemID: String, text: String) {
        ensure(itemID)
        guard items[itemID]?.final == nil else { return }
        items[itemID]?.delta += text
        revision += 1
    }

    mutating func committed(itemID: String, previousItemID: String?) {
        ensure(itemID)
        items[itemID]?.committed = true
        items[itemID]?.predecessor = previousItemID
        revision += 1
    }

    mutating func completed(itemID: String, transcript: String) {
        ensure(itemID)
        items[itemID]?.final = transcript
        revision += 1
    }

    private mutating func ensure(_ id: String) {
        if items[id] == nil { items[id] = Item(sequence: items.count) }
    }

    private var orderedIDs: [String] {
        var ordered: [String] = [], visited = Set<String>()
        func visit(_ id: String) {
            guard !visited.contains(id), let item = items[id] else { return }
            visited.insert(id)
            if let previous = item.predecessor, items[previous]?.committed == true { visit(previous) }
            ordered.append(id)
        }
        let sorted = items.keys.sorted { items[$0]!.sequence < items[$1]!.sequence }
        for id in sorted where items[id]?.committed == true { visit(id) }
        for id in sorted where !visited.contains(id) { ordered.append(id) }
        return ordered
    }
}

struct LiveTurnSegmenter {
    private var samples = 0
    private var silentSamples = 0
    private var hasSpeech = false
    var duration: TimeInterval { Double(samples) / 24_000 }

    mutating func append(_ chunk: LiveAudioChunk) -> Bool {
        samples += chunk.sampleCount
        if chunk.rms >= 0.008 { hasSpeech = true; silentSamples = 0 } else { silentSamples += chunk.sampleCount }
        return samples >= 45 * 24_000 || (hasSpeech && silentSamples >= 19_200 && samples >= 7200)
    }

    mutating func reset() { self = LiveTurnSegmenter() }

    /// The 300ms floor is an internal padding policy, not a documented server minimum.
    var finalPadding: Data? { finalPadding(allowSilenceOnly: true) }

    func finalPadding(allowSilenceOnly: Bool) -> Data? {
        guard samples > 0, hasSpeech || (allowSilenceOnly && samples >= 7200) else { return nil }
        return Data(repeating: 0, count: max(0, 7200 - samples) * 2)
    }
}
