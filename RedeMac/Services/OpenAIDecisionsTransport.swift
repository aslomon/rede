import Foundation

struct OpenAIDecisionsTransport: Sendable {
    static let shared = OpenAIDecisionsTransport()
    static let requestTimeout: TimeInterval = 10
    static let resourceTimeout: TimeInterval = 15
    static let endpoint = URL(string: "https://api.openai.com/v1/decisions")!
    private static let sharedSession = makeSession()

    private let apiKey: @Sendable () -> String?
    private let session: URLSession
    private let isRemoteAllowed: @Sendable () -> Bool

    init(
        session: URLSession = sharedSession,
        isRemoteAllowed: @escaping @Sendable () -> Bool = { true },
        apiKey: @escaping @Sendable () -> String? = { KeychainService.load(key: .openAIAPIKey) }
    ) {
        self.session = session
        self.apiKey = apiKey
        self.isRemoteAllowed = isRemoteAllowed
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    static func makeSession(configuration: URLSessionConfiguration = makeConfiguration()) -> URLSession {
        URLSession(configuration: configuration, delegate: DecisionsRedirectDelegate(), delegateQueue: nil)
    }

    func send(_ body: Data) async throws -> DecisionsHTTPResponse {
        try Task.checkCancellation()
        guard isRemoteAllowed() else { throw RemoteRequestBlocked() }
        guard body.count <= DecisionsClient.maximumRequestBytes else { throw DecisionsClientError.invalidRequest }
        let credential = try await DecisionsCredentialLoader.shared.load(apiKey, isRemoteAllowed: isRemoteAllowed)
        try Task.checkCancellation()
        guard let key = credential?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DecisionsClientError.notConfigured
        }
        guard isRemoteAllowed() else { throw RemoteRequestBlocked() }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.requestTimeout
        request.httpBody = body
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength <= Int64(DecisionsClient.maximumResponseBytes)
        else {
            throw DecisionsClientError.invalidResponse
        }
        let data = try await Self.receive(bytes)
        return DecisionsHTTPResponse(data: data, statusCode: response.statusCode)
    }

    private static func receive(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        let task = bytes.task
        return try await withTaskCancellationHandler {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < DecisionsClient.maximumResponseBytes else {
                    throw DecisionsClientError.invalidResponse
                }
                data.append(byte)
            }
            return data
        } onCancel: {
            task.cancel()
        }
    }
}

private final class DecisionsRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Caller evidence must stay on the single documented HTTPS endpoint, even after a redirect.
        completionHandler(nil)
    }
}
