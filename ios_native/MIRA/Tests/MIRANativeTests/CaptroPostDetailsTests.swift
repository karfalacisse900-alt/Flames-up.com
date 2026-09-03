import XCTest
@testable import MIRANative

final class CaptroPostDetailsTests: XCTestCase {
  func testExplicitTypesSelectSpecializedLayouts() throws {
    let cases: [(String, CaptroPostDetailKind)] = [
      ("place", .placeReview), ("check_in", .placeReview),
      ("general", .regular), ("video", .regular), ("note", .regular),
      ("meetup", .event), ("event", .event),
      ("concert", .event), ("travel", .travel), ("boarding_pass", .travel),
      ("receipt", .receipt), ("invoice", .invoice),
      ("collection", .collection), ("list", .collection), ("guide", .collection),
    ]
    for (type, expected) in cases {
      let post = try decode(["id": "post", "post_type": type])
      XCTAssertEqual(post.detailKind, expected, type)
    }
  }

  func testTravelAndDocumentStampsContainOnlyPreviewFacts() throws {
    let travel = try decode(["id": "travel", "post_type": "travel", "user_username": "traveler",
      "detail": ["travel": ["operator": "Rail operator", "origin_code": "AAA", "destination_code": "BBB",
        "duration": "1h", "departure": "10:30 AM", "passenger_email": "private@example.com", "code": "PRIVATE"]]])
    XCTAssertEqual(travel.captroStampContent.title, "Rail operator")
    XCTAssertEqual(travel.captroStampContent.metadata, "AAA → BBB")
    XCTAssertFalse(travel.captroStampContent.description?.contains("PRIVATE") ?? true)
    let receipt = try decode(["id": "receipt", "post_type": "receipt", "detail": ["document": [
      "merchant_name": "Market", "total": "20.02", "currency": "USD", "verdict": "Unable to Verify"]]])
    XCTAssertEqual(receipt.captroStampContent.title, "Market")
    XCTAssertEqual(receipt.captroStampContent.description, "USD 20.02\nUnable to Verify")
  }

  func testRegularPostWithTaggedPlaceIsStillRegular() throws {
    let post = try decode(["id": "post", "post_type": "general", "place_name": "Tagged place"])
    XCTAssertEqual(post.detailKind, .regular)
    XCTAssertNotNil(post.detailMapURL)
  }

  func testFullCaptionKeepsEveryLine() throws {
    let caption = String(repeating: "A complete caption line.\n", count: 30).trimmingCharacters(in: .whitespacesAndNewlines)
    let post = try decode(["id": "post", "title": "Title", "caption": caption])
    XCTAssertEqual(post.detailCaption, caption)
    let fallback = try decode(["id": "post", "caption": "  ", "content": caption])
    XCTAssertEqual(fallback.detailCaption, caption)
  }

  func testDetailSurvivesEngagementPinningAndCacheRoundTrip() throws {
    let post = try decode([
      "id": "event", "post_type": "event",
      "detail": [
        "visited_count": 8,
        "event": [
          "starts_at": "2026-09-12T23:00:00Z",
          "attendees_count": 23,
          "viewer_going": true,
          "attendance_enabled": true,
        ],
      ],
    ])
    let updated = post.updating(liked: true, likesCount: 4, saved: true).updatingPinned(at: "2026-09-01T00:00:00Z")
    XCTAssertEqual(updated.detail, post.detail)
    let data = try JSONEncoder().encode(updated)
    let restored = try JSONDecoder().decode(MIRAPost.self, from: data)
    XCTAssertEqual(restored.detail?.event?.attendeesCount, 23)
    XCTAssertEqual(restored.detail?.event?.viewerGoing, true)
  }

  func testMissingEnrichmentDoesNotInventEventFacts() throws {
    let post = try decode(["id": "post", "post_type": "meetup", "caption": "Saturday at seven, 23 going"])
    XCTAssertNil(post.detail?.event?.startsAt)
    XCTAssertNil(post.detail?.event?.attendeesCount)
    XCTAssertNil(post.detail?.event?.attendanceEnabled)
    XCTAssertNil(post.detail?.visitedCount)
    XCTAssertNil(post.detailMapURL)
  }

  func testCollectionUsesRealUniqueChildPosts() throws {
    let post = try decode([
      "id": "collection", "post_type": "collection",
      "detail": ["collection": ["items": [
        ["id": "place-1", "post_type": "place", "place_name": "First place"],
        ["id": "place-1", "post_type": "place"],
        ["id": "collection", "post_type": "collection"],
        ["id": "place-2", "post_type": "place", "place_name": "Second place"],
      ]]],
    ])
    XCTAssertEqual(post.detailCollectionItems.map(\.id), ["place-1", "place-2"])
    XCTAssertEqual(post.detailCollectionItems.first?.placeDisplayName, "First place")
  }

  func testMapLinkSafelyEncodesAddressAndIgnoresInvalidCoordinates() throws {
    let post = try decode([
      "id": "place", "place_name": "Cafe & Bakery",
      "place_formatted_address": "12 Main St #2", "place_lat": 900, "place_lng": 1000,
    ])
    let url = try XCTUnwrap(post.detailMapURL)
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.host, "maps.apple.com")
    XCTAssertEqual(components.queryItems?.first?.value, "Cafe & Bakery, 12 Main St #2")
    XCTAssertFalse(components.queryItems?.contains(where: { $0.name == "ll" }) ?? true)
  }

  func testEventDateSupportsFractionalSecondsAndInvalidDates() throws {
    let post = try decode([
      "id": "event", "detail": ["event": [
        "starts_at": "2026-09-12T23:00:00.000Z", "ends_at": "not-a-date", "time_zone": "America/New_York",
      ]],
    ])
    XCTAssertNotNil(post.detail?.event?.startDate)
    XCTAssertNil(post.detail?.event?.endDate)
    XCTAssertNotNil(post.detail?.event?.calendarDate)
    XCTAssertNotNil(post.detail?.event?.timeRange)
  }

  private func decode(_ json: [String: Any]) throws -> MIRAPost {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject: json))
  }
}
