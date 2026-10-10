import XCTest
@testable import MIRANative

final class CaptroCompositionTests: XCTestCase {
  func testCoverDefaultsAndTypographyAreRealNativeFonts() throws {
    let writing = CaptroMediaWriting.cover(sourceAspectRatio: 9.0 / 16)
    XCTAssertEqual(writing.y, 0.46); XCTAssertEqual(writing.alignment, "center")
    XCTAssertEqual(writing.showsStamp, false); XCTAssertEqual(writing.characterLimit, 70)
    XCTAssertEqual(writing.homeAspectRatio ?? 0, 9.0 / 16, accuracy: 0.001)
    XCTAssertEqual(writing.color, "black"); XCTAssertTrue(writing.readability)
    XCTAssertEqual(writing.font(mediaWidth: 390).fontName, "WalterTurncoat-Regular", "The licensed hand-lettered face must load, without the old brush script")
    XCTAssertEqual(writing.font(mediaWidth: 390).pointSize, 22.23, accuracy: 0.1)
    var short = writing; short.text = "FRIDAY NIGHT\nIN NYC"
    XCTAssertNil(short.validationMessage)
    XCTAssertLessThan(short.measuredSize(mediaWidth: 390).width + 14, 390 * 0.60,
      "A short headline must have a content-sized label, not a full-width banner")
    XCTAssertEqual(short.font(mediaWidth: 390).pointSize, writing.font(mediaWidth: 390).pointSize,
      "Short phrases must not scale larger than long ones")
    for phrase in ["NIGHTLIFE FRIDAY IN NYC", "INTIMATE JAZZ CLUBS WORTH SAVING",
      "NEIGHBORHOOD THAI RESTAURANTS", "THE NEW YORK GIFT GUIDE",
      "COZY ITALIAN\nRESTAURANTS\nWITH HANDMADE\nPASTA TO KNOW\nIN NEW YORK"] {
      short.text = phrase
      XCTAssertNil(short.validationMessage, "The automatic Cover treatment must fit \(phrase)")
    }
    short.text = String(repeating: "a", count: 71)
    XCTAssertNotNil(short.validationMessage); XCTAssertEqual(short.text.count, 71)
    let restored = try JSONDecoder().decode(CaptroMediaWriting.self, from: JSONEncoder().encode(writing))
    XCTAssertEqual(restored, writing)
  }
  func testFeedMixesCoversOtherMediaAndTextWithoutLosingRankWithinEachFormat() {
    let ranked = ["cover-1", "cover-2", "cover-3", "photo-1", "photo-2", "text-1", "text-2"]
    let mixed = CaptroFeedFormatMixer.mix(ranked) { item in String(item.split(separator: "-")[0]) }
    XCTAssertEqual(mixed, ["cover-1", "photo-1", "text-1", "cover-2", "photo-2", "text-2", "cover-3"])
    XCTAssertEqual(CaptroFeedFormatMixer.mix(["cover-1", "cover-2"]) { _ in "cover" }, ["cover-1", "cover-2"])
  }
  func testCoverCropKeepsMediaAndWritingInTheSameCoordinateSpace() {
    var writing = CaptroMediaWriting.cover(sourceAspectRatio: 9.0 / 16)
    writing.text = "LITTLE MOMENTS"; writing.cropY = 0.7
    let canvas = CGSize(width: 390, height: 390 / (writing.homeAspectRatio ?? 1))
    let source = writing.sourceRect(in: canvas, fill: true)
    let text = writing.textRect(in: canvas, fill: true)
    XCTAssertEqual(source.minY, (canvas.height - source.height) * 0.7, accuracy: 0.001)
    XCTAssertEqual(text.midY, source.minY + source.height * writing.y, accuracy: 0.001)
    XCTAssertLessThan(source.minY, 0, "Home preview crops; original metadata is preserved")
    XCTAssertEqual(MIRAMediaSizing.homeHeightToWidthRatios.count, 4)
    XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(16.0 / 9), 5.0 / 4, accuracy: 0.001)
    XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(9.0 / 16), 9.0 / 16, accuracy: 0.001)
    XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(1), 1, accuracy: 0.001)
    XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(5.0 / 4), 5.0 / 4, accuracy: 0.001)
    XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(4.0 / 3), 4.0 / 3, accuracy: 0.001)
    XCTAssertGreaterThan(MIRAMediaSizing.homeDisplayRatio(4.0 / 3), MIRAMediaSizing.homeDisplayRatio(1))
  }
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
    XCTAssertEqual(draft.intent, .free)
    XCTAssertEqual(CaptroWritingIntent.allCases.count, 5)
    XCTAssertEqual(draft.intent.byline, "")
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
    XCTAssertNil(draft.submittedIntent)
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
