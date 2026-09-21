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
  func testMomentDoesNotRepeatAuthorOrDateAndFeedSizingStaysResponsive() {
    let moment = CaptroStampContent(kind: .social, title: "NYC Ferry", metadata: nil,
      description: nil, footer: "@captro · Sep 20", actionTitle: nil, contributors: [])
    XCTAssertEqual(moment.displayFields["compactText"], "")
    XCTAssertFalse(moment.displayFields.values.contains(where: { $0.contains("@captro") }))
    XCTAssertEqual(CaptroStampLayout.feedWidth(for: 320), 184)
    XCTAssertEqual(CaptroStampLayout.feedWidth(for: 390), 210.6, accuracy: 0.01)
    XCTAssertEqual(CaptroStampLayout.feedWidth(for: 430), 214)
  }
  func testImportantEventTitleCanUseTwoLinesWithoutEllipsis() throws {
    let template = try XCTUnwrap(CaptroStampTemplate.catalog["event-ticket"])
    let title = try XCTUnwrap(template.compact.fields.first(where: { $0.key == "title" }))
    let lines = try XCTUnwrap(title.fittedLines("Bronx Run Club", maximumLines: 2))
    XCTAssertEqual(lines.map(\.0).joined(separator: " "), "Bronx Run Club")
    XCTAssertEqual(lines.count, 2)
    XCTAssertFalse(lines.contains(where: { $0.0.contains("…") }))
    let club = try XCTUnwrap(CaptroStampTemplate.catalog["club-oval"]?.compact.fields.first(where: { $0.key == "title" }))
    XCTAssertTrue(club.fits("Yoga NYC", size: club.size))
  }

  func testEditorialCardUsesOneDesignForMomentAndAttachedKinds() {
    let mappings: [(CaptroStampKind, CaptroEditorialCardType)] = [
      (.social, .moment), (.place, .place), (.club, .club), (.event, .event),
      (.meetup, .meetup), (.deal, .deal)
    ]
    for (kind, expected) in mappings {
      XCTAssertEqual(CaptroEditorialCardType(stampKind: kind), expected)
    }
    XCTAssertEqual(CaptroEditorialCardType(stampKind: .travel), .moment)
    XCTAssertEqual(CaptroEditorialCardLayout.width(for: 320), 233.6, accuracy: 0.01)
    XCTAssertEqual(CaptroEditorialCardLayout.width(for: 390), 284.7, accuracy: 0.01)
    XCTAssertTrue(CaptroEditorialCardLayout.isCondensed(mediaWidth: 390, mediaHeight: 219))
    XCTAssertFalse(CaptroEditorialCardLayout.isCondensed(mediaWidth: 390, mediaHeight: 488))
  }

  func testEditorialPlaceUsesPostDataAndDoesNotInventMissingCounts() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let withCount = try decoder.decode(MIRAPost.self, from: Data(#"{"id":"post","post_type":"place","place_name":"Ruffian","display_location_label":"East Village","saves_count":469,"caption":"An intimate wine bar.","user_username":"atlanta_gao"}"#.utf8))
    let card = withCount.captroEditorialCardContent
    XCTAssertEqual(card.type, .place)
    XCTAssertEqual(card.title, "Ruffian")
    XCTAssertEqual(card.chipText, "469 SAVES")
    XCTAssertEqual(card.username, "@atlanta_gao")
    let noCount = try decoder.decode(MIRAPost.self, from: Data(#"{"id":"post","post_type":"place","place_name":"Ruffian"}"#.utf8))
    XCTAssertNil(noCount.captroEditorialCardContent.chipText)
  }

  func testEditorialDealDoesNotInventBenefitOrLoseConditions() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let json = #"{"id":"post","post_type":"deal","detail":{"commerce":{"id":"offer","content_type":"deal","fulfillment_type":"redemption","payment_model":"free","commerce_class":"commerce","title":"Joe's Pizza","description":"Offer details","joined_count":0,"refund_policy":"none","approval_required":false,"pass_required":false,"status":"expired","audience":"public","public_data":{"benefits":["20% Off"],"redemption_rules":"Spend $20+"},"prices":[]}}}"#
    let post = try decoder.decode(MIRAPost.self, from: Data(json.utf8))
    let card = post.captroEditorialCardContent
    XCTAssertEqual(card.title, "Joe's Pizza")
    XCTAssertEqual(card.chipText, "Expired")
    XCTAssertEqual(card.supportingText, "Spend $20+")
  }

  func testVoiceMomentAndStampedVoicePostsUseTheSameCard() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let moment = try decoder.decode(MIRAPost.self, from: Data(#"{"id":"voice","post_type":"general","caption":"Walking home","detail":{"voice":{"id":"audio-1","duration_ms":42000}}}"#.utf8))
    XCTAssertEqual(moment.captroEditorialCardContent.type, .moment)
    XCTAssertEqual(moment.captroEditorialCardContent.title, "Voice post")
    XCTAssertEqual(moment.captroEditorialCardContent.description, "Walking home")

    for kind in CaptroStampKind.creationCases {
      let body = CreatePostBody(title: "Test", content: "A recorded post", image: nil,
        images: [], mediaTypes: [], mediaDimensions: [], postType: kind.backendPostType,
        voiceAudioId: "audio-1", visibility: "public", clientRequestId: "request-1")
      XCTAssertEqual(body.postType, kind.backendPostType)
      XCTAssertEqual(body.voiceAudioId, "audio-1")
    }
  }
}
