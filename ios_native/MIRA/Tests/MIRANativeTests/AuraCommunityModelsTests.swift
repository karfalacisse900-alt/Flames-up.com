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

  func testCommunityVideoDecodesCanonicalReferenceTypePosterAndAssetIdentity() throws {
    let data = Data(
      """
      {
        "id": "post-video-1",
        "title": "Neighborhood basketball",
        "post_type": "small_post",
        "image": "cfstream:stream-uid-123",
        "images": ["cfstream:stream-uid-123"],
        "feed_media_urls": ["https://videodelivery.net/stream-uid-123/manifest/video.m3u8"],
        "thumbnail_urls": ["https://videodelivery.net/stream-uid-123/thumbnails/thumbnail.jpg"],
        "poster_urls": ["https://videodelivery.net/stream-uid-123/thumbnails/thumbnail.jpg"],
        "media_types": ["video"],
        "media_asset_ids": ["asset-video-1"]
      }
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let post = try decoder.decode(AuraCommunityPost.self, from: data)

    XCTAssertEqual(post.primaryMediaReference, "cfstream:stream-uid-123")
    XCTAssertEqual(post.primaryMediaType, "video")
    XCTAssertTrue(post.containsVideoMedia)
    XCTAssertEqual(post.primaryPosterURL, "https://videodelivery.net/stream-uid-123/thumbnails/thumbnail.jpg")
    XCTAssertEqual(post.primaryPlaybackURL, "https://videodelivery.net/stream-uid-123/manifest/video.m3u8")
    XCTAssertEqual(post.primaryImageURL, post.primaryPosterURL)
    XCTAssertEqual(post.mediaAssetIds, ["asset-video-1"])
  }

  func testCommunityPhotoKeepsFeedDeliveryURLAndImageType() throws {
    let data = Data(
      """
      {
        "id": "post-photo-1",
        "post_type": "meetup",
        "image": "https://imagedelivery.net/account/image-id/public",
        "images": ["https://imagedelivery.net/account/image-id/public"],
        "feed_media_urls": ["https://imagedelivery.net/account/image-id/feed"],
        "media_types": ["image"],
        "media_asset_ids": ["asset-image-1"]
      }
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let post = try decoder.decode(AuraCommunityPost.self, from: data)

    XCTAssertEqual(post.primaryMediaType, "image")
    XCTAssertFalse(post.containsVideoMedia)
    XCTAssertEqual(post.primaryMediaReference, "https://imagedelivery.net/account/image-id/public")
    XCTAssertEqual(post.primaryImageURL, "https://imagedelivery.net/account/image-id/feed")
    XCTAssertEqual(post.mediaAssetIds, ["asset-image-1"])
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
      hasPhoto: true,
      mediaKind: "video",
      mediaFileName: "meetup.mov",
      mediaMimeType: "video/quicktime"
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
    XCTAssertEqual(decoded.mediaKind, "video")
    XCTAssertEqual(decoded.mediaFileName, "meetup.mov")
    XCTAssertEqual(decoded.mediaMimeType, "video/quicktime")
  }

  func testCommunityDraftDecodesLegacyPhotoWithoutMediaMetadata() throws {
    let legacy = Data(
      """
      {
        "mode": "small_post",
        "title": "Coffee",
        "bodyText": "Quiet corner",
        "category": "recommendation",
        "audience": "public",
        "allowReplies": true,
        "neighborhood": "SoHo",
        "startsAt": "2026-08-26T14:00:00Z",
        "endsAt": "2026-08-26T15:00:00Z",
        "entryType": "free",
        "entryAmountAUR": "",
        "maxPeople": 12,
        "hasPhoto": true
      }
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(AuraCommunityDraft.self, from: legacy)

    XCTAssertTrue(decoded.hasPhoto)
    XCTAssertNil(decoded.mediaKind)
    XCTAssertNil(decoded.mediaFileName)
    XCTAssertNil(decoded.mediaMimeType)
  }
}
