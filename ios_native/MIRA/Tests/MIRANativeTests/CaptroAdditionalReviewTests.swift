import XCTest
@testable import MIRANative

final class CaptroAdditionalReviewTests: XCTestCase {
  func testProfileLinksValidateOnlyCanonicalAppRoutes() throws {
    let url = try XCTUnwrap(CaptroProfileLink.url(userID: "owner-123"))
    XCTAssertEqual(CaptroProfileLink.parse(url)?.id, "owner-123")
    for value in ["captro://profile/a/b", "captro://profile/../b", "https://evil.invalid/profile/a", "captro://profile/a?token=secret", "captro://profile/a#b"] {
      XCTAssertNil(CaptroProfileLink.parse(try XCTUnwrap(URL(string: value))))
    }
    XCTAssertNil(CaptroProfileLink.url(userID: "../admin"))
    XCTAssertNil(CaptroProfileLink.url(userID: ""))
  }

  func testOptionalProfileFieldsDecodeWithoutInventingCountsOrPendingRequests() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let user = try decoder.decode(MIRAUser.self, from: Data(#"{"id":"private","privacy_locked":true,"follow_pending":true}"#.utf8))
    XCTAssertNil(user.followersCount)
    XCTAssertNil(user.openTo)
    XCTAssertEqual(user.followPending, true)
    XCTAssertEqual(user.privacyLocked, true)
    let old = try decoder.decode(MIRAUser.self, from: Data(#"{"id":"old"}"#.utf8))
    XCTAssertNil(old.followPending)
  }
  func testExactCurrencyParsingAndSupportedPrecision() {
    let us = Locale(identifier: "en_US")
    XCTAssertEqual(CaptroMoney.parse("10.00", currency: "USD", locale: us), 1000)
    XCTAssertEqual(CaptroMoney.parse("1,000", currency: "JPY", locale: us), 1000)
    XCTAssertEqual(CaptroMoney.parse("10,00", currency: "USD", locale: Locale(identifier: "de_DE")), 1000)
    XCTAssertNil(CaptroMoney.parse("10.001", currency: "USD", locale: us))
    XCTAssertNil(CaptroMoney.parse("1000.1", currency: "JPY", locale: us))
    XCTAssertNil(CaptroMoney.parse("10,00", currency: "USD", locale: us))
    XCTAssertNil(CaptroMoney.parse("1000", currency: "ISK", locale: us))
    XCTAssertNil(CaptroMoney.parse("1e3", currency: "USD", locale: us))
    XCTAssertFalse(CaptroMoney.format(minorUnits: 1000, currency: "JPY").contains("10.00"))
  }

  func testStoryExpiryUsesIndividualDatesAndFailsClosedForUnknownExpiry() throws {
    let json = """
    [{"userId":"owner","statuses":[
      {"id":"old","userId":"owner","expiresAt":"2035-01-01T10:00:00Z"},
      {"id":"valid","userId":"owner","expiresAt":"2035-01-01T11:00:00.000Z"},
      {"id":"missing","userId":"owner"},
      {"id":"invalid","userId":"owner","expiresAt":"not-a-date"}
    ]}]
    """
    let groups = try JSONDecoder().decode([MIRAStoryGroup].self, from: Data(json.utf8))
    let now = try XCTUnwrap(CaptroStoryExpiry.date("2035-01-01T10:00:00Z"))
    XCTAssertEqual(CaptroStoryExpiry.groups(groups, at: now).first?.statuses?.map(\.id), ["valid"])
    XCTAssertEqual(CaptroStoryExpiry.groups(groups, at: now).first?.id, groups.first?.id)
    XCTAssertTrue(CaptroStoryExpiry.groups(groups, at: now.addingTimeInterval(3600)).isEmpty)
    XCTAssertEqual(groups.first?.statuses?.count, 4) // no destructive stored-data edit
    let separate = try JSONDecoder().decode([MIRAStoryGroup].self, from: Data("[{\"userId\":\"same\",\"statuses\":[{\"id\":\"one\",\"userId\":\"same\",\"expiresAt\":\"2035-01-01T11:00:00Z\"}]},{\"userId\":\"same\",\"statuses\":[{\"id\":\"two\",\"userId\":\"same\",\"expiresAt\":\"2035-01-01T11:00:00Z\"}]}]".utf8))
    XCTAssertEqual(CaptroStoryExpiry.groups(separate, at: now).map(\.id), ["one", "two"])
  }

  func testEventPriceEditPreservesCurrencyPrecisionAndFreeFacts() {
    var draft = CaptroEventDraft()
    draft.currency = "JPY"; draft.hasPrice = true; draft.price = "1000"
    XCTAssertNil(draft.validationError)
    XCTAssertEqual(draft.input.price, "1000")
    draft.price = "1000.01"
    XCTAssertNotNil(draft.validationError)
    draft.price = "0"
    XCTAssertNil(draft.validationError)
    XCTAssertEqual(draft.input.price, "0")
    draft.currency = "ISK"
    XCTAssertNotNil(draft.validationError)
  }
}
