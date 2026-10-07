import XCTest
@testable import MIRANative

final class CaptroCompositionTests: XCTestCase {
  func testNewMediaLimitsDoNotTruncateDraftOrReduceTextOnlyAndStructuredDescriptions() {
    var draft = CaptroCompositionDraft()
    draft.bodyText = String(repeating: "a", count: 500)
    XCTAssertNil(draft.writingValidationMessage)
    draft.mediaItems = [MIRAPickedMedia(data: Data([1]), kind: .image, fileName: "test.jpg", mimeType: "image/jpeg")]
    XCTAssertEqual(draft.bodyCharacterLimit, 220)
    XCTAssertNotNil(draft.writingValidationMessage)
    XCTAssertEqual(draft.bodyText.count, 500, "Preserve pasted/restored writing for correction")
    draft.bodyText = String(repeating: "👨‍👩‍👧‍👦", count: 220)
    XCTAssertNil(draft.writingValidationMessage)
    draft.title = String(repeating: "a", count: 61)
    XCTAssertNotNil(draft.titleValidationMessage)
    draft.title = "An actual title"
    draft.selectedStampKind = .club
    draft.bodyText = String(repeating: "a", count: 500)
    XCTAssertEqual(draft.bodyCharacterLimit, 500)
    XCTAssertNil(draft.writingValidationMessage)
  }
  func testDefaultAndIntentChangesKeepWritingAttachmentsAndSchedule() {
    var draft = CaptroCompositionDraft()
    XCTAssertEqual(draft.intent, .wantTo)
    XCTAssertEqual(CaptroWritingIntent.allCases.count, 3)
    XCTAssertEqual(draft.intent.byline, "wants to")
    draft.bodyText = "A designer and developer."
    let attachment = MIRAPickedMedia(data: Data([1, 2, 3]), kind: .image,
      fileName: "draft-test.jpg", mimeType: "image/jpeg")
    draft.mediaItems = [attachment]
    draft.originalMediaItems = [attachment]
    draft.time = Date(timeIntervalSince1970: 1_800_000_000)
    let id = draft.requestID
    draft.intent = .concern
    XCTAssertNil(draft.submittedTime)
    XCTAssertNotNil(draft.time)
    XCTAssertEqual(draft.bodyText, "A designer and developer.")
    XCTAssertEqual(draft.mediaItems, [attachment])
    XCTAssertEqual(draft.originalMediaItems, [attachment])
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
  func testTypingLimitNeverTruncatesRestoredTextOrComposition() {
    XCTAssertFalse(CaptroCompositionTextView.permitsChange(from: String(repeating: "a", count: 500),
      to: String(repeating: "a", count: 501)))
    let restored = String(repeating: "a", count: 550)
    XCTAssertFalse(CaptroCompositionTextView.permitsChange(from: restored, to: restored + "b"))
    XCTAssertTrue(CaptroCompositionTextView.permitsChange(from: restored, to: String(restored.dropLast())))
    XCTAssertTrue(CaptroCompositionTextView.permitsChange(from: String(repeating: "a", count: 499),
      to: String(repeating: "a", count: 499) + "👨‍👩‍👧‍👦"))
    XCTAssertTrue(CaptroCompositionTextView.permitsChange(from: "hello", to: restored, composing: true))
  }
}
