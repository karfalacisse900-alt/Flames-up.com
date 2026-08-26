import Foundation
import XCTest
@testable import MIRANative

final class AuraCommunityModelsTests: XCTestCase {
  func testCommunityFeedArrayDecodesAllRecordsInsteadOfOnlyTheFirst() throws {
    let data = Data(
      """
      [
        {
          "id": "post-small-array-1",
          "title": "Question",
          "post_type": "small_post",
          "community_category": "question"
        },
        {
          "id": "post-meetup-array-1",
          "title": "Coffee meetup",
          "post_type": "meetup",
          "meetup_entry_type": "free",
          "meetup_joined_count": 2
        },
        {
          "id": "post-small-array-2",
          "content": "An update without optional media or location fields.",
          "post_type": "small_post",
          "community_category": "update"
        }
      ]
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let posts = try decoder.decode([AuraCommunityPost].self, from: data)

    XCTAssertEqual(posts.map(\.id), ["post-small-array-1", "post-meetup-array-1", "post-small-array-2"])
    XCTAssertEqual(posts.map(\.mode), [.smallPost, .meetup, .smallPost])
  }

  func testTextOnlySmallPostDecodesFromCommunityAPI() throws {
    let data = Data(
      """
      {
        "id": "post-small-1",
        "user_id": "user-1",
        "user_username": "auramember",
        "title": "Late-night study spot",
        "content": "Quiet place, good wifi, and open late.",
        "post_type": "small_post",
        "community_category": "recommendation",
        "community_audience": "friends",
        "community_allow_replies": true,
        "comments_count": 3,
        "created_at": "2026-08-25T18:00:00Z"
      }
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let post = try decoder.decode(AuraCommunityPost.self, from: data)

    XCTAssertEqual(post.mode, .smallPost)
    XCTAssertEqual(post.authorHandle, "@auramember")
    XCTAssertEqual(post.titleText, "Late-night study spot")
    XCTAssertEqual(post.bodyText, "Quiet place, good wifi, and open late.")
    XCTAssertNil(post.primaryImageURL)
    XCTAssertEqual(post.communityCategory, "recommendation")
    XCTAssertEqual(post.commentsCount, 3)
  }

  func testMeetupUsesExactAtomicAmountForEntryLabel() throws {
    let data = Data(
      """
      {
        "id": "post-meetup-1",
        "title": "Funny Study Group",
        "content": "Come study and meet new people.",
        "post_type": "meetup",
        "place_name": "Blank Street Coffee",
        "meetup_neighborhood": "SoHo",
        "meetup_entry_type": "aur",
        "meetup_entry_amount_atoms": "10000000000",
        "meetup_max_people": 12,
        "meetup_state_available": true,
        "meetup_joined_count": 4
      }
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let post = try decoder.decode(AuraCommunityPost.self, from: data)

    XCTAssertEqual(post.mode, .meetup)
    XCTAssertEqual(post.entryLabel, "100 AUR")
    XCTAssertEqual(post.locationLine, "Blank Street Coffee · SoHo")
    XCTAssertEqual(post.meetupJoinedCount, 4)
  }

  func testFreeMeetupDoesNotInventAttendanceOrPayment() throws {
    let data = Data(
      """
      {
        "id": "post-meetup-2",
        "title": "Neighborhood walk",
        "post_type": "meetup",
        "meetup_entry_type": "free",
        "meetup_state_available": false
      }
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let post = try decoder.decode(AuraCommunityPost.self, from: data)

    XCTAssertEqual(post.entryLabel, "FREE")
    XCTAssertNil(post.meetupJoinedCount)
    XCTAssertEqual(post.meetupStateAvailable, false)
  }

  func testCommunityDraftCodableRoundTripPreservesMeetupFields() throws {
    let startsAt = Date(timeIntervalSince1970: 1_777_000_000)
    let draft = AuraCommunityDraft(
      mode: .meetup,
      title: "Coffee meetup",
      bodyText: "Bring a book.",
      category: .idea,
      audience: .friends,
      allowReplies: true,
      neighborhood: "SoHo",
      startsAt: startsAt,
      endsAt: startsAt.addingTimeInterval(5_400),
      entryType: .aur,
      entryAmountAUR: "2.5",
      maxPeople: 8,
      placeProvider: "apple_maps",
      placeProviderId: "place-1",
      placeName: "Coffee Shop",
      placeFormattedAddress: "123 Prince Street, New York, NY",
      placeLatitude: 40.72,
      placeLongitude: -74.00,
      placeCategory: "coffee_shop",
      placeCity: "New York",
      placeRegion: "NY",
      placeCountry: "US",
      hasPhoto: true
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(AuraCommunityDraft.self, from: encoder.encode(draft))

    XCTAssertEqual(decoded.mode, .meetup)
    XCTAssertEqual(decoded.title, draft.title)
    XCTAssertEqual(decoded.entryType, .aur)
    XCTAssertEqual(decoded.entryAmountAUR, "2.5")
    XCTAssertEqual(decoded.maxPeople, 8)
    XCTAssertEqual(decoded.placeProviderId, "place-1")
    XCTAssertTrue(decoded.hasPhoto)
  }
}
