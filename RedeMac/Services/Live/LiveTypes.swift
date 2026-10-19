import Foundation

struct LiveTranscriptSnapshot: Equatable, Sendable {
    var stableText = ""
    var provisionalText = ""
    var revision = 0
    var text: String {
        [stableText, provisionalText].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum LiveFailure: Error, Equatable, Sendable {
    case remoteNotAllowed, unauthorized, modelUnavailable, network, timeout
    case protocolViolation, server(code: String), captureFailed
}

struct LiveStats: Equatable, Sendable {
    var sentAudioSeconds: Double = 0
    /// Number of commit send attempts, including correlated commit_empty rejections.
    var localCommitCount = 0
    var completedItemCount = 0
    var firstDeltaLatency: TimeInterval?
}

enum LiveOutcome: Equatable, Sendable {
    case transcript(String, LiveStats)
    case unusable(LiveFailure)
    case cancelled
}

struct LiveConfiguration: Equatable, Sendable {
    enum Delay: String, Sendable { case minimal, low, medium, high, xhigh }
    var language = "de"
    var keywords: [String] = []
    var delay: Delay = .low
    var connectionTimeout: Duration = .seconds(8)
    var finalizationTimeout: Duration = .seconds(5)
}

struct LiveAudioChunk: Equatable, Sendable {
    let pcm16: Data
    let rms: Float
    var sampleCount: Int { pcm16.count / 2 }
    var duration: TimeInterval { Double(sampleCount) / 24_000 }
}

@MainActor protocol LiveAudioSource: AnyObject {
    func start() throws -> AsyncThrowingStream<LiveAudioChunk, Error>
    /// Ends capture and finishes the stream after its buffered PCM tail has been emitted.
    func stop()
}

@MainActor protocol LiveSocketTransport: AnyObject {
    func connect(apiKey: String) async throws
    func send(_ event: Data) async throws
    func receive() async throws -> Data
    func close()
}

struct TranscriptionCapabilities: Equatable, Sendable {
    var streamsPartialText: Bool
    var needsNetwork: Bool
    var wordTimestamps: Bool
    var confidence: Bool
    var speakerLabels: Bool
    var detectsLanguage: Bool

    static let engines: [String: TranscriptionCapabilities] = [
        "gpt-live-transcribe": .init(streamsPartialText: true, needsNetwork: true,
                                     wordTimestamps: false, confidence: false,
                                     speakerLabels: false, detectsLanguage: false),
        "gpt-transcribe": .init(streamsPartialText: false, needsNetwork: true,
                                wordTimestamps: false, confidence: false, speakerLabels: false, detectsLanguage: true),
        "whisper-1": .init(streamsPartialText: false, needsNetwork: true,
                           wordTimestamps: true, confidence: false, speakerLabels: false, detectsLanguage: false),
        "local-whisper": .init(streamsPartialText: false, needsNetwork: false,
                               wordTimestamps: false, confidence: false, speakerLabels: false, detectsLanguage: false)
    ]
}

enum LiveAvailability: Equatable, Sendable {
    enum Reason: Equatable, Sendable { case featureOff, secureLocal, localBackend, noAPIKey, noMicrophone }
    case available
    case unavailable(Reason)

    static func resolve(featureEnabled: Bool, secureLocal: Bool, backendIsRemote: Bool,
                        hasAPIKey: Bool, microphoneAuthorized: Bool) -> LiveAvailability {
        if !featureEnabled { return .unavailable(.featureOff) }
        if secureLocal { return .unavailable(.secureLocal) }
        if !backendIsRemote { return .unavailable(.localBackend) }
        if !hasAPIKey { return .unavailable(.noAPIKey) }
        return microphoneAuthorized ? .available : .unavailable(.noMicrophone)
    }
}
