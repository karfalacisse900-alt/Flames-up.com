import XCTest
@testable import MIRANative

final class CaptroStampTests: XCTestCase {
  func testNativeCatalogAndFontMeasurements() throws {
    XCTAssertEqual(CaptroStampTemplate.catalog.count, 15)
    for template in CaptroStampTemplate.catalog.values {
      for layout in [template.compact, template.full] {
        XCTAssertEqual(layout.width, 640)
        XCTAssertFalse(layout.layers.isEmpty)
        for field in layout.fields {
          let (text, size) = field.fitted(String(repeating: "Long price condition ", count: 20))
          XCTAssertTrue(field.fits(text, size: size), "\(template.id) \(field.key)")
        }
      }
    }
  }
  func testOneTimeAndRecurringRemainDifferent() throws {
    func price(_ period: String) throws -> CaptroCommercePrice {
      let json: [String: Any] = ["id":"price", "label":"Access", "unitAmount":800,
        "currency":"USD", "billingPeriod":period, "active":true]
      return try JSONDecoder().decode(CaptroCommercePrice.self, from: JSONSerialization.data(withJSONObject: json))
    }
    XCTAssertTrue(try XCTUnwrap(price("one_time").stampPrice).contains("one time"))
    XCTAssertTrue(try XCTUnwrap(price("month").stampPrice).contains("/month"))
    XCTAssertNil(try price("unknown").stampPrice)
  }
  func testUnknownVariantAndSavedExpiredDealDoNotOverwriteTerms() {
    let content = CaptroStampContent(kind: .deal, title: "20% off", metadata: nil, description: nil,
      footer: nil, actionTitle: nil, contributors: [], variant: "club-oval", terms: "$20 minimum spend",
      availability: "Expired", relationship: "Saved", postID: "post", attachmentID: "offer")
    XCTAssertEqual(content.resolvedVariant, "deal-coupon")
    XCTAssertEqual(content.displayFields["compactText"], "$20 minimum spend")
    XCTAssertTrue(content.accessibleStampLabel.contains("Expired"))
    XCTAssertTrue(content.accessibleStampLabel.contains("Saved"))
    XCTAssertNotEqual(content.postID, content.attachmentID)
  }
  func testLegacyPostAndVariantSurviveReload() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let post = try decoder.decode(MIRAPost.self, from: Data(#"{"id":"post","post_type":"club","stamp_variant":"club-tag"}"#.utf8))
    XCTAssertEqual(post.captroStampContent.resolvedVariant,"club-tag")
    let restored = try JSONDecoder().decode(MIRAPost.self, from: JSONEncoder().encode(post))
    XCTAssertEqual(restored.stampVariant,"club-tag")
    XCTAssertEqual(post.updating(liked: true).stampVariant,"club-tag")
  }
}
