import Foundation

/// Detects the host's memory, chip and free disk, and turns that into a concrete model
/// recommendation. All values are read once and are cheap; callers may refresh on demand.
struct SystemCapabilities: Equatable {
  /// Total physical RAM in gigabytes. Uses GiB (base-1024) because Apple markets unified memory
  /// in GiB labelled "GB" (a 48 GiB Mac is sold as "48GB"), so this reads "48 GB", not "52".
  let totalRAMGB: Double
  /// Free space on the home volume in gigabytes (base-1000, matching how the Finder reports disk).
  let freeDiskGB: Double
  /// Marketing chip string, e.g. "Apple M3 Max".
  let chipName: String
  /// Whether this is Apple Silicon (unified memory → models share system RAM).
  let isAppleSilicon: Bool

  /// How a given memory requirement fits this machine.
  enum Fit: Equatable {
    /// Comfortable: leaves plenty of headroom for the OS and other apps.
    case comfortable
    /// Tight: runs, but with little headroom — expect some slowdown when multitasking.
    case tight
    /// Too large: would not fit safely and is likely to swap or fail.
    case tooLarge
  }

  /// Fraction of total RAM we treat as safely usable for a model (rest stays for OS + apps).
  /// Apple Silicon's unified memory is efficient, so we allow a bit more than on Intel.
  private var usableRAMGB: Double {
    totalRAMGB * (isAppleSilicon ? 0.70 : 0.55)
  }

  /// "Comfortable" budget — what we recommend staying under for a smooth everyday experience.
  private var comfortableRAMGB: Double {
    totalRAMGB * (isAppleSilicon ? 0.55 : 0.45)
  }

  /// Classify a model's estimated runtime RAM against this machine.
  func fit(forRuntimeRAMGB ram: Double) -> Fit {
    if ram <= comfortableRAMGB { return .comfortable }
    if ram <= usableRAMGB { return .tight }
    return .tooLarge
  }

  /// Whether the model's download still fits on the free disk (with a small safety margin).
  func diskFits(downloadGB: Double) -> Bool {
    downloadGB + 2.0 <= freeDiskGB
  }

  /// The single best model to recommend: the highest-quality catalog entry whose estimated
  /// runtime RAM stays within the *comfortable* budget and whose download fits on disk.
  /// Falls back to the best one that merely fits (`tight`), then to the smallest model.
  func recommendedModel(from catalog: [LlamaCppModelCatalog.Model] = LlamaCppModelCatalog.models)
    -> LlamaCppModelCatalog.Model?
  {
    let byQuality = catalog.sorted { $0.qualityRank > $1.qualityRank }

    if let best = byQuality.first(where: {
      diskFits(downloadGB: $0.downloadGB)
        && fit(forRuntimeRAMGB: $0.estimatedRuntimeRAMGB) == .comfortable
    }) {
      return best
    }
    if let fits = byQuality.first(where: {
      diskFits(downloadGB: $0.downloadGB)
        && fit(forRuntimeRAMGB: $0.estimatedRuntimeRAMGB) != .tooLarge
    }) {
      return fits
    }
    return catalog.min { $0.downloadGB < $1.downloadGB }
  }

  /// Human-readable reason for the recommendation, e.g. "Passt komfortabel in deine 48 GB RAM".
  func recommendationReason(for model: LlamaCppModelCatalog.Model) -> String {
    switch fit(forRuntimeRAMGB: model.estimatedRuntimeRAMGB) {
    case .comfortable:
      return "Beste Qualität, die komfortabel in deine \(formattedRAM) RAM passt."
    case .tight:
      return "Passt gerade so in deine \(formattedRAM) RAM — schließe ggf. andere Apps."
    case .tooLarge:
      return "Kleinstes verfügbares Modell für deine \(formattedRAM) RAM."
    }
  }

  /// "48 GB" style label.
  var formattedRAM: String {
    SystemCapabilities.formatGB(totalRAMGB)
  }

  /// "75 GB" style label.
  var formattedFreeDisk: String {
    SystemCapabilities.formatGB(freeDiskGB)
  }

  /// Compact GB formatter shared by labels: no decimals at/above 10 GB, one below.
  static func formatGB(_ value: Double) -> String {
    if value >= 10 { return "\(Int(value.rounded())) GB" }
    return String(format: "%.1f GB", value).replacingOccurrences(of: ".", with: ",")
  }

  // MARK: - Detection

  /// Read the current machine's capabilities. Cheap; safe to call on the main actor.
  static func current() -> SystemCapabilities {
    SystemCapabilities(
      totalRAMGB: detectTotalRAMGB(),
      freeDiskGB: detectFreeDiskGB(),
      chipName: detectChipName(),
      isAppleSilicon: detectIsAppleSilicon()
    )
  }

  private static func detectTotalRAMGB() -> Double {
    // GiB (base-1024): physicalMemory on a "48GB" Mac is 48 * 1024³ bytes → 48.0, not 51.5.
    Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
  }

  private static func detectFreeDiskGB() -> Double {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    let bytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
    return Double(bytes) / 1_000_000_000.0
  }

  private static func detectChipName() -> String {
    sysctlString("machdep.cpu.brand_string") ?? "Unbekannter Prozessor"
  }

  private static func detectIsAppleSilicon() -> Bool {
    (sysctlString("machdep.cpu.brand_string") ?? "").localizedCaseInsensitiveContains("Apple")
  }

  /// Read a string-valued sysctl by name (e.g. "machdep.cpu.brand_string").
  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
  }
}
