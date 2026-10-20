import XCTest
@testable import MIRANative

final class CaptroCreatorSupportTests: XCTestCase {
  @MainActor func testReturnOriginSurvivesRestartButNeverCrossesAccountsOrExpiry() {
    let defaults = UserDefaults(suiteName: "support-return-\(UUID().uuidString)")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let id = UUID().uuidString
    let first = CaptroSupportReturnStore(defaults: defaults, clock: { now })
    first.remember(handoffID: id, buyerID: "buyer", creatorID: "creator", postID: "post")
    let restarted = CaptroSupportReturnStore(defaults: defaults, clock: { now })
    XCTAssertEqual(restarted.origin(handoffID: id, buyerID: "buyer")?.postID, "post")
    XCTAssertNil(restarted.origin(handoffID: id, buyerID: "other-account"))
    XCTAssertNil(restarted.origin(handoffID: UUID().uuidString, buyerID: "buyer"))
    let expired = CaptroSupportReturnStore(defaults: defaults, clock: { now.addingTimeInterval(8 * 86400) })
    XCTAssertNil(expired.origin(handoffID: id, buyerID: "buyer"))
    restarted.forget(accountID: "buyer")
    XCTAssertNil(restarted.origin(handoffID: id, buyerID: "buyer"))
  }
  func testSupportAmountsAreExactAndBounded() {
    let locale = Locale(identifier: "en_US")
    XCTAssertEqual(CaptroSupportPolicy.amount("2", locale: locale), 200)
    XCTAssertEqual(CaptroSupportPolicy.amount("10.01", locale: locale), 1001)
    for value in ["1.99", "200.01", "5.005", "-5", "NaN", "2e2"] {
      XCTAssertNil(CaptroSupportPolicy.amount(value, locale: locale))
    }
  }
  func testStorefrontIsNotLocaleOrIP() {
    XCTAssertTrue(CaptroSupportPolicy.permits(storefront: "USA"))
    for code in [nil, "US", "GBR", "en_US"] { XCTAssertFalse(CaptroSupportPolicy.permits(storefront: code)) }
  }
  func testOnlyScopedOwnedHTTPSHandoffOpens() {
    let token = String(repeating: "a", count: 64)
    XCTAssertNotNil(CaptroSupportPolicy.handoffURL("https://flames-up.com/support-creator/#handoff=\(token)", amount: 500))
    for url in ["http://flames-up.com/support-creator/#handoff=\(token)",
      "https://evil.test/support-creator/#handoff=\(token)",
      "https://flames-up.com@evil.test/support-creator/#handoff=\(token)",
      "https://flames-up.com/support-creator/?redirect=evil#handoff=\(token)"] {
      XCTAssertNil(CaptroSupportPolicy.handoffURL(url, amount: 500))
    }
  }
  func testReturnIsAReferenceNotProofOfPayment() {
    let id = UUID().uuidString
    XCTAssertEqual(CaptroSupportPolicy.returnPurchase(URL(string: "https://flames-up.com/support-creator/return?purchase_id=\(id)")!), id)
    XCTAssertNil(CaptroSupportPolicy.returnPurchase(URL(string: "https://evil.test/support-creator/return?purchase_id=\(id)")!))
    XCTAssertNil(CaptroSupportPolicy.returnPurchase(URL(string: "https://flames-up.com/support-creator/return?purchase_id=\(id)&purchase_id=\(id)")!))
  }
}
