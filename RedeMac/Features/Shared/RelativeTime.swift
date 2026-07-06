import Foundation

enum RelativeTime {
  static func short(
    _ date: Date,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> String {
    let interval = now.timeIntervalSince(date)
    guard interval >= 60 else { return "gerade eben" }

    if interval < 60 * 60 {
      let minutes = max(1, Int(interval / 60))
      return "vor \(minutes) min"
    }

    if calendar.isDate(date, inSameDayAs: now) {
      let hours = max(1, Int(interval / (60 * 60)))
      return "vor \(hours) std"
    }

    if isYesterday(date, now: now, calendar: calendar) {
      return "gestern"
    }

    return shortDate(date, calendar: calendar)
  }

  private static func isYesterday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
    let dateStart = calendar.startOfDay(for: date)
    let nowStart = calendar.startOfDay(for: now)
    let components = calendar.dateComponents([.day], from: dateStart, to: nowStart)
    return components.day == 1
  }

  private static func shortDate(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "d.M."
    return formatter.string(from: date)
  }
}
