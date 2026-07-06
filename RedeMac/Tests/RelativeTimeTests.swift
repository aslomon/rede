import XCTest

@testable import Rede

final class RelativeTimeTests: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }()

  func testSubMinuteIsJustNow() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 0, second: 0)
    let date = now.addingTimeInterval(-59)

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "gerade eben")
  }

  func testOneMinuteStartsMinuteOutput() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 0, second: 0)
    let date = now.addingTimeInterval(-60)

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "vor 1 min")
  }

  func testFiftyNineMinutesUsesMinutes() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 0, second: 0)
    let date = now.addingTimeInterval(-59 * 60)

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "vor 59 min")
  }

  func testSixtyMinutesOnSameDayUsesHours() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 0, second: 0)
    let date = now.addingTimeInterval(-60 * 60)

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "vor 1 std")
  }

  func testSameDayHoursUseRoundedDownHourCount() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 30, second: 0)
    let date = now.addingTimeInterval(-(2 * 60 * 60 + 45 * 60))

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "vor 2 std")
  }

  func testYesterdayUsesCalendarDayNotHourDistance() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 0, second: 0)
    let date = try self.date(year: 2026, month: 7, day: 5, hour: 23, minute: 55, second: 0)

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "gestern")
  }

  func testOlderDateUsesGermanShortDayMonth() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 0, second: 0)
    let date = try self.date(year: 2026, month: 6, day: 30, hour: 8, minute: 0, second: 0)

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "30.6.")
  }

  func testFutureDateIsJustNow() throws {
    let now = try date(year: 2026, month: 7, day: 6, hour: 12, minute: 0, second: 0)
    let date = now.addingTimeInterval(10)

    XCTAssertEqual(RelativeTime.short(date, now: now, calendar: calendar), "gerade eben")
  }

  private func date(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int
  ) throws -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return try XCTUnwrap(calendar.date(from: components))
  }
}
