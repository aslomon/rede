import OSLog

enum LiveDiagnostics {
    private static let logger = Logger(subsystem: "app.rede.mac", category: "LiveTranscription")

    static func checkCommitCount(local: Int, server: Int) {
        guard server > local else { return }
        logger.error("Live commit count mismatch: local=\(local), server=\(server)")
    }
}
