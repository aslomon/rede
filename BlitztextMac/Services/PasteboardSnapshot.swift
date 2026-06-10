import AppKit

/// A deep, value-type copy of every item currently on an `NSPasteboard`.
///
/// Used by the auto-paste flow to preserve whatever the user already had on the clipboard:
/// rede overwrites the pasteboard with the dictated text, simulates Cmd+V, and then —
/// once the target app has consumed our text — restores this snapshot so the user's previous
/// clipboard (and any sensitive transcript) does not linger.
///
/// Items are copied eagerly (types + their raw `data(forType:)`) into detached
/// `NSPasteboardItem`s, so the snapshot stays valid even after `clearContents()` is called on
/// the live pasteboard.
struct PasteboardSnapshot {
  /// One captured item: each pasteboard type mapped to its raw bytes (if any).
  private let items: [[NSPasteboard.PasteboardType: Data]]

  /// Nothing was on the pasteboard (or every item was empty) — restore is a no-op.
  var isEmpty: Bool { items.allSatisfy { $0.isEmpty } }

  private init(items: [[NSPasteboard.PasteboardType: Data]]) {
    self.items = items
  }

  /// Eagerly copies every item + every type's data off `pasteboard`. Types without retrievable
  /// data are skipped (some promised types have no bytes yet) rather than failing the whole capture.
  static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
    let captured: [[NSPasteboard.PasteboardType: Data]] =
      (pasteboard.pasteboardItems ?? []).map { item in
        var typeData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
          if let data = item.data(forType: type) {
            typeData[type] = data
          }
        }
        return typeData
      }
    return PasteboardSnapshot(items: captured)
  }

  /// Rebuilds detached `NSPasteboardItem`s from the snapshot and writes them back. No-op when
  /// empty, so an empty snapshot never clobbers whatever is on the pasteboard at restore time.
  func restore(to pasteboard: NSPasteboard) {
    guard !isEmpty else { return }
    let rebuilt: [NSPasteboardItem] = items.compactMap { typeData in
      guard !typeData.isEmpty else { return nil }
      let item = NSPasteboardItem()
      for (type, data) in typeData {
        item.setData(data, forType: type)
      }
      return item
    }
    guard !rebuilt.isEmpty else { return }
    pasteboard.clearContents()
    pasteboard.writeObjects(rebuilt)
  }
}
