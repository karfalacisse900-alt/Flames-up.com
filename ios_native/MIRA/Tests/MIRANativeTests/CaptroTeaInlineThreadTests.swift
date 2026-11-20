import XCTest
import UIKit
@testable import MIRANative

final class CaptroTeaInlineThreadTests: XCTestCase {
  private func note(_ body: String, sentences: [CaptroTeaReplyTarget], counts: [CaptroTeaReplyCount]) -> CaptroTeaConversation {
    .init(id: "note", title: "Nightlife NYC", body: body, links: [], author: .init(id: "author", name: "Author", username: "author"), createdAt: "now", version: 1, isAuthor: false, following: false, sentences: sentences, replyTargets: counts)
  }
  func testOverlappingExcerptsUseOneMarkerAndPreserveOriginalTargets() throws {
    let sentence = CaptroTeaReplyTarget(id: "1:0:25", version: 1, start: 0, end: 25, quote: "Good music and good food.")
    let first = try XCTUnwrap(sentence.selection(NSRange(location: 0, length: 10)))
    let overlap = try XCTUnwrap(sentence.selection(NSRange(location: 5, length: 10)))
    let counts = [CaptroTeaReplyCount(target: first,count: 2), .init(target: overlap,count: 1), .init(target: first,count: 2)]
    let groups = note(sentence.quote,sentences: [sentence],counts: counts).inlineThreads
    XCTAssertEqual(groups.count,1); XCTAssertEqual(groups[0].count,3)
    XCTAssertEqual(Set(groups[0].targets.map(\.target.quote)),[first.quote,overlap.quote])
  }
  func testEditedCaptionCannotAdoptAnEarlierQuote() {
    let previous = CaptroTeaReplyTarget(id: "1:0:5",version: 1,start: 0,end: 5,quote: "Hello")
    let current = CaptroTeaReplyTarget(id: "2:0:5",version: 2,start: 0,end: 5,quote: "Other")
    let groups = note("Other",sentences: [current],counts: [.init(target: previous,count: 2)]).inlineThreads
    XCTAssertEqual(groups[0].count,0); XCTAssertTrue(groups[1].earlier)
    XCTAssertEqual(groups[1].sentence.quote,"Hello")
  }
  @MainActor func testHundredAnchorsAreCollapsedLazyAndOnlyOneCanOpen() async {
    let anchors = (0..<100).map { CaptroTeaReplyTarget(id: "1:\($0 * 10):\($0 * 10 + 9)",version:1,start:$0 * 10,end:$0 * 10 + 9,quote:"Sentence.") }
    let post = note(anchors.map(\.quote).joined(separator:" "),sentences:anchors,counts:anchors.map { .init(target:$0,count:1) })
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [InlineReplyProtocol.self]
    let session = URLSession(configuration:config); defer { session.invalidateAndCancel() }
    InlineReplyProtocol.reset()
    let api = MIRAAPIClient(session:session)
    let model = api.teaConversations.model(for:post)
    XCTAssertEqual(post.inlineThreads.count,100); XCTAssertTrue(model.expandedTargets.isEmpty)
    XCTAssertTrue(InlineReplyProtocol.requests.isEmpty)
    model.draft = "Keep draft"
    model.toggleThread(post.inlineThreads[0])
    for _ in 0..<30 { if !InlineReplyProtocol.requests.isEmpty { break }; try? await Task.sleep(nanoseconds:10_000_000) }
    model.toggleThread(post.inlineThreads[1])
    for _ in 0..<30 { if InlineReplyProtocol.requests.count >= 2 { break }; try? await Task.sleep(nanoseconds:10_000_000) }
    XCTAssertEqual(model.expandedTargets,[post.inlineThreads[1].id])
    XCTAssertLessThanOrEqual(InlineReplyProtocol.requests.count,2)
    XCTAssertTrue(InlineReplyProtocol.requests.allSatisfy { $0.contains("target=sentence:") })
    model.toggleThread(post.inlineThreads[1]); XCTAssertTrue(model.expandedTargets.isEmpty)
    XCTAssertEqual(model.draft,"Keep draft")
    model.clear(); XCTAssertTrue(model.threads.isEmpty)
  }
}

private final class InlineReplyProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var paths: [String] = []
  static var requests: [String] { lock.withLock { paths } }
  static func reset() { lock.withLock { paths = [] } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.withLock { Self.paths.append(request.url!.absoluteString) }
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
    client?.urlProtocol(self,didLoad:Data(#"{"items":[]}"#.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
