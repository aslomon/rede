import Foundation

@MainActor final class URLSessionLiveSocket: LiveSocketTransport {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    func connect(apiKey: String) async throws {
        close()
        let configuration = Self.makeConfiguration()
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 1_048_576
        self.session = session
        self.task = task
        task.resume()
    }

    /// The controller independently owns its eight-second handshake deadline.
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        return configuration
    }

    func send(_ event: Data) async throws {
        guard let task, let text = String(data: event, encoding: .utf8) else { throw LiveFailure.protocolViolation }
        try await task.send(.string(text))
    }

    func receive() async throws -> Data {
        guard let task else { throw LiveFailure.network }
        do {
            switch try await task.receive() {
            case .data(let data): return data
            case .string(let text): return Data(text.utf8)
            @unknown default: throw LiveFailure.protocolViolation
            }
        } catch {
            if let status = (task.response as? HTTPURLResponse)?.statusCode {
                if [401, 403].contains(status) { throw LiveFailure.unauthorized }
                if status == 404 { throw LiveFailure.modelUnavailable }
            }
            throw error
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }
}
