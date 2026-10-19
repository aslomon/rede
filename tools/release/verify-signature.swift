import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
  let publicData = Data(base64Encoded: CommandLine.arguments[2]),
  let signature = Data(base64Encoded: CommandLine.arguments[3])
else { exit(2) }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
guard key.isValidSignature(signature, for: archive) else { exit(1) }
print("Ed25519 signature verified against pinned public key")
