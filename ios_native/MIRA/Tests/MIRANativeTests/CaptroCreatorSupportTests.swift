import XCTest
@testable import MIRANative

final class CaptroCreatorSupportTests: XCTestCase {
  func testCreatorPoolsDecodeUnknownFeesWithoutInventingAvailableMoney() throws {
    let data = Data(#"{"mode":"test","payoutScope":"creator_currency_all_categories_fifo","pools":[{"category":"creator_support","currency":"USD","transactions":1,"grossReceived":500,"refunded":0,"captroFee":0,"processingFees":null,"creatorNet":null,"pending":500,"available":0,"paidOut":0,"held":0}]}"#.utf8)
    let response = try JSONDecoder().decode(CaptroEarningsPoolsResponse.self, from: data)
    let pool = try XCTUnwrap(response.pools.first)
    XCTAssertEqual(pool.title, "Support")
    XCTAssertEqual(pool.id, "creator_support:USD")
    XCTAssertNil(pool.processingFees)
    XCTAssertNil(pool.creatorNet)
    XCTAssertEqual(pool.available, 0)
    XCTAssertEqual(pool.money(nil), "Awaiting Stripe fees")
  }

  func testCategoryPayoutAttributionIsNotAnotherPayoutOrFee() throws {
    let data = Data(#"{"category":"creator_support","currency":"USD","section":"payouts","items":[{"id":"payout-1","status":"paid","attributedAmount":441,"payoutAmount":1381,"payoutFee":0,"currency":"USD"}],"nextOffset":null}"#.utf8)
    let page = try JSONDecoder().decode(CaptroEarningsPoolPage<CaptroPoolPayout>.self, from: data)
    XCTAssertEqual(page.items.first?.attributedAmount, 441)
    XCTAssertEqual(page.items.first?.payoutAmount, 1381)
    XCTAssertEqual(page.items.first?.payoutFee, 0)
    XCTAssertNil(page.nextOffset)
  }

  func testReadinessKeepsCaptroFlagsDistinctFromStripeRequirements() throws {
    let data = Data(#"{"status":"blocked","retryable":false,"blockers":[{"source":"captro","code":"rollout_disabled","message":"Test only"},{"source":"stripe","code":"transfers_inactive","message":"Transfers inactive"}]}"#.utf8)
    let readiness = try JSONDecoder().decode(CaptroSupportReadiness.self, from: data)
    XCTAssertEqual(readiness.blockers.map(\.sourceLabel), ["Captro", "Stripe"])
    XCTAssertNotEqual(readiness.blockers[0].id, readiness.blockers[1].id)
  }
  func testRecipientUsesDisplayNameAndNeverShowsBlankIdentity() {
    XCTAssertEqual(CaptroSupportPolicy.recipientName("  Fixture Creator  ", fallback: "@fixture"), "Fixture Creator")
    XCTAssertEqual(CaptroSupportPolicy.recipientName(" \n ", fallback: "@fixture"), "@fixture")
    XCTAssertEqual(CaptroSupportPolicy.recipientName(nil, fallback: "@fixture"), "@fixture")
  }
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
    XCTAssertNotNil(CaptroSupportPolicy.handoffURL("https://captro-site.pages.dev/support-creator/#handoff=\(token)", amount: 500))
    for url in ["http://captro-site.pages.dev/support-creator/#handoff=\(token)",
      "https://evil.test/support-creator/#handoff=\(token)",
      "https://captro-site.pages.dev@evil.test/support-creator/#handoff=\(token)",
      "https://captro-site.pages.dev/support-creator/?redirect=evil#handoff=\(token)",
      "https://flames-up.com/support-creator/#handoff=\(token)"] {
      XCTAssertNil(CaptroSupportPolicy.handoffURL(url, amount: 500))
    }
  }
  func testReturnIsAReferenceNotProofOfPayment() {
    let id = UUID().uuidString
    XCTAssertEqual(CaptroSupportPolicy.returnPurchase(URL(string: "https://captro-site.pages.dev/support-creator/return?purchase_id=\(id)")!), id)
    XCTAssertNil(CaptroSupportPolicy.returnPurchase(URL(string: "https://evil.test/support-creator/return?purchase_id=\(id)")!))
    XCTAssertNil(CaptroSupportPolicy.returnPurchase(URL(string: "https://captro-site.pages.dev/support-creator/return?purchase_id=\(id)&purchase_id=\(id)")!))
  }
}
