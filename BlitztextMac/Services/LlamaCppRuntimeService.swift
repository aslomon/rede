import Darwin
import Foundation

actor LlamaCppRuntimeService {
  static let shared = LlamaCppRuntimeService()

  enum RuntimeError: LocalizedError {
    case helperMissing
    case helperNotExecutable
    case modelUnknown(String)
    case modelNotInstalled(String)
    case portOwnershipMismatch
    case startupTimedOut
    case processLaunchFailed(String)

    var errorDescription: String? {
      switch self {
      case .helperMissing:
        return "Der llama.cpp-Helfer ist noch nicht in Blitztext gebündelt."
      case .helperNotExecutable:
        return "Der llama.cpp-Helfer ist nicht ausführbar."
      case .modelUnknown(let modelID):
        return "Unbekanntes lokales Modell: \(modelID)"
      case .modelNotInstalled(let modelID):
        return "Das lokale Modell „\(modelID)“ ist noch nicht installiert."
      case .portOwnershipMismatch:
        return "Der lokale llama.cpp-Port gehört nicht zum gestarteten Blitztext-Helper."
      case .startupTimedOut:
        return "llama.cpp konnte das Modell nicht rechtzeitig starten."
      case .processLaunchFailed(let message):
        return "llama.cpp konnte nicht gestartet werden: \(message)"
      }
    }
  }

  private struct RunningServer {
    let process: Process
    let modelID: String
    let client: LlamaCppServerClient
  }

  private let store: LlamaCppModelStore
  private var running: RunningServer?

  init(store: LlamaCppModelStore = .default) {
    self.store = store
  }

  func client(for modelID: String) async throws -> LlamaCppServerClient {
    let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    if let running, running.modelID == trimmed, running.process.isRunning {
      let status = await running.client.healthStatus()
      if status == .ready { return running.client }
    }

    try await stop()
    let model = try modelEntry(for: trimmed)
    let modelURL = try store.finalURL(for: model)
    guard store.isInstalled(model) else {
      throw RuntimeError.modelNotInstalled(trimmed)
    }
    guard try store.verifyFileChecksum(for: model) else {
      throw RuntimeError.modelNotInstalled(trimmed)
    }

    let executableURL = try Self.bundledExecutableURL()
    let port = try Self.findFreeLocalPort()
    let apiKey = UUID().uuidString
    let client = LlamaCppServerClient(
      baseURL: URL(string: "http://127.0.0.1:\(port)")!,
      apiKey: apiKey
    )

    let process = Process()
    process.executableURL = executableURL
    process.arguments = Self.launchArguments(
      modelURL: modelURL,
      port: port,
      alias: trimmed,
      contextSize: 4096,
      apiKey: apiKey
    )
    process.environment = Self.sanitizedEnvironment()
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
      try process.run()
    } catch {
      throw RuntimeError.processLaunchFailed(error.localizedDescription)
    }

    running = RunningServer(process: process, modelID: trimmed, client: client)
    do {
      try await waitUntilReady(client: client, process: process)
      guard Self.listeningPIDs(for: port).contains(process.processIdentifier) else {
        throw RuntimeError.portOwnershipMismatch
      }
    } catch {
      try? await stop()
      throw error
    }
    return client
  }

  func stop() async throws {
    guard let server = running else { return }
    running = nil
    guard server.process.isRunning else { return }
    server.process.terminate()
    try await Task.sleep(nanoseconds: 500_000_000)
    if server.process.isRunning {
      kill(server.process.processIdentifier, SIGKILL)
    }
  }

  private func modelEntry(for modelID: String) throws -> LlamaCppModelCatalog.Model {
    guard let model = LlamaCppModelCatalog.model(for: modelID) else {
      throw RuntimeError.modelUnknown(modelID)
    }
    return model
  }

  private func waitUntilReady(client: LlamaCppServerClient, process: Process) async throws {
    let deadline = Date().addingTimeInterval(120)
    while Date() < deadline {
      guard process.isRunning else {
        throw RuntimeError.processLaunchFailed("Der Helper-Prozess wurde beendet.")
      }
      let status = await client.healthStatus()
      if status == .ready { return }
      try await Task.sleep(nanoseconds: 500_000_000)
    }
    throw RuntimeError.startupTimedOut
  }

  static func bundledExecutableURL() throws -> URL {
    #if DEBUG
      if let override = ProcessInfo.processInfo.environment["BLITZTEXT_LLAMA_SERVER"],
        !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return try validatedExecutableURL(URL(fileURLWithPath: override))
      }
    #endif

    let bundleURL = Bundle.main.bundleURL
    let candidate = bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true)
      .appendingPathComponent("llama-server", isDirectory: false)
    return try validatedExecutableURL(candidate)
  }

  static func executableURLOverride(_ url: URL) -> URL {
    url
  }

  static func launchArguments(
    modelURL: URL,
    port: Int,
    alias: String,
    contextSize: Int,
    apiKey: String
  ) -> [String] {
    [
      "--host", "127.0.0.1",
      "--port", "\(port)",
      "--model", modelURL.path,
      "--alias", alias,
      "--ctx-size", "\(contextSize)",
      "--api-key", apiKey,
      "--no-webui",
      "--log-disable",
    ]
  }

  static func findFreeLocalPort() throws -> Int {
    for _ in 0..<100 {
      let port = Int.random(in: 49152...65535)
      if portIsAvailable(port) { return port }
    }
    throw RuntimeError.processLaunchFailed("Kein freier lokaler Port gefunden.")
  }

  private static func validatedExecutableURL(_ url: URL) throws -> URL {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw RuntimeError.helperMissing
    }
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      throw RuntimeError.helperNotExecutable
    }
    return url
  }

  private static func sanitizedEnvironment() -> [String: String] {
    ProcessInfo.processInfo.environment.filter { key, _ in
      !key.hasPrefix("DYLD_")
    }
  }

  private static func portIsAvailable(_ port: Int) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }

    var value: Int32 = 1
    setsockopt(
      descriptor,
      SOL_SOCKET,
      SO_REUSEADDR,
      &value,
      socklen_t(MemoryLayout<Int32>.size)
    )

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return result == 0
  }

  static func parseListeningPIDs(_ output: String) -> Set<Int32> {
    Set(
      output
        .split(whereSeparator: \.isNewline)
        .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    )
  }

  private static func listeningPIDs(for port: Int) -> Set<Int32> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      return parseListeningPIDs(String(data: data, encoding: .utf8) ?? "")
    } catch {
      return []
    }
  }
}

struct LlamaCppRewriteProvider: RewriteProvider {
  let modelID: String
  let runtime: LlamaCppRuntimeService

  init(modelID: String, runtime: LlamaCppRuntimeService = .shared) {
    self.modelID = modelID
    self.runtime = runtime
  }

  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws
    -> RewriteOutcome
  {
    let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LLMError.localModelUnavailable(
        "Kein lokales llama.cpp-Modell ausgewählt. Lade zuerst ein GGUF-Modell in den Einstellungen."
      )
    }

    do {
      let client = try await runtime.client(for: trimmed)
      let text = try await client.chatCompletion(
        modelID: trimmed,
        systemPrompt: systemPrompt,
        userText: userText,
        temperature: temperature
      )
      return RewriteOutcome(text: text, usedModelID: trimmed, requestedModelID: trimmed)
    } catch let runtimeError as LlamaCppRuntimeService.RuntimeError {
      throw LLMError.localModelUnavailable(
        runtimeError.localizedDescription
      )
    }
  }
}
