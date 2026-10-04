import XCTest
@testable import MIRANative

final class CaptroCompositionTests: XCTestCase {
  func testDefaultAndIntentChangesKeepWritingAttachmentsAndSchedule() {
    var draft = CaptroCompositionDraft()
    XCTAssertEqual(draft.intent, .wantTo)
    XCTAssertEqual(CaptroWritingIntent.allCases.count, 3)
    XCTAssertEqual(draft.intent.byline, "wants to")
    draft.bodyText = "A designer and developer."
    draft.time = Date(timeIntervalSince1970: 1_800_000_000)
    let id = draft.requestID
    draft.intent = .concern
    XCTAssertNil(draft.submittedTime)
    XCTAssertNotNil(draft.time)
    XCTAssertEqual(draft.bodyText, "A designer and developer.")
    XCTAssertEqual(draft.requestID, id)
    draft.intent = .lookingFor
    XCTAssertNotNil(draft.submittedTime)
    XCTAssertEqual(draft.submittedIntent, "looking_for")
    draft.selectedStampKind = .event
    XCTAssertNil(draft.submittedIntent)
    XCTAssertNil(draft.submittedTime)
  }
  func testWhitespaceAndGraphemeCounting() {
    var draft = CaptroCompositionDraft()
    draft.bodyText = " \n "
    XCTAssertFalse(draft.hasWriting)
    let emoji = "👨‍👩‍👧‍👦"
    XCTAssertEqual(emoji.count, 1)
    draft.bodyText = String(repeating: emoji, count: 500)
    XCTAssertEqual(draft.bodyText.count, 500)
    XCTAssertTrue(draft.hasWriting)
  }
  func testDraftRoundTripKeepsRequestIntentAudienceTime() throws {
    let old = #"{"title":"","bodyText":"hello","hashtags":[],"showBroadLocation":false,"media":[],"uploadStatus":"draft","savedAt":"2026-10-04T12:00:00Z"}"#
    var snapshot = try JSONDecoder().decode(MIRAPostDraftSnapshot.self, from: Data(old.utf8))
    XCTAssertNil(snapshot.creationIntent)
    snapshot.creationIntent = "looking_for"
    snapshot.audience = "friends"
    snapshot.compositionTime = Date(timeIntervalSince1970: 1_800_000_000)
    snapshot.clientRequestID = UUID().uuidString
    let restored = try JSONDecoder().decode(MIRAPostDraftSnapshot.self, from: JSONEncoder().encode(snapshot))
    XCTAssertEqual(restored, snapshot)
  }
}

