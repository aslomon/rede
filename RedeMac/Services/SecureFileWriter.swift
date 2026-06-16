import Foundation

/// Writes data to disk with owner-only POSIX permissions (0600) and enforces them
/// even when the file already exists. Used for the opt-in archive + memory stores
/// so personal text/PII never becomes group/other readable.
enum SecureFileWriter {
  static func write(_ data: Data, to url: URL) throws {
    // Atomic write first (creates with the process umask), then tighten permissions.
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o600))],
      ofItemAtPath: url.path
    )
  }
}
