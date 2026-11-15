import XCTest
import Foundation
@testable import MIRANative

final class CaptroTeaClubTests: XCTestCase {
  @MainActor func testClubCacheScopesDraftsAndEvictsWithoutResurrectingPrivateContent() {
    MIRALocalJSONCache.setAccountScope(userId: "club-a")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let api = MIRAAPIClient()
    let first = api.teaClubs.model("one")
    first.drafts["general"] = "Unsent private draft"
    XCTAssertTrue(first === api.teaClubs.model("one"))
    first.room = "room-two"; first.drafts[first.key] = "Room draft"
    first.room = nil; XCTAssertEqual(first.drafts[first.key], "Unsent private draft")
    MIRALocalJSONCache.setAccountScope(userId: "club-b")
    let next = api.teaClubs.model("one")
    XCTAssertFalse(first.valid); XCTAssertTrue(first.drafts.isEmpty); XCTAssertFalse(next === first)
    next.drafts["general"] = "Must be evicted"
    for n in 1...13 { _ = api.teaClubs.model("club-\(n)") }
    XCTAssertFalse(next.valid); XCTAssertTrue(next.drafts.isEmpty)
    XCTAssertTrue(api.teaClubs.model("one").valid)
    api.teaClubs.invalidate(); XCTAssertFalse(api.teaClubs.model("one") === next)
  }

  @MainActor func testRequestsCoalesceAndRevocationClearsMessagesDraftAndLinks() async {
    ClubTestProtocol.reset()
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ClubTestProtocol.self]
    let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
    let api = MIRAAPIClient(session: session)
    let model = api.teaClubs.model("club")
    async let first: Void = model.load()
    async let second: Void = model.load()
    _ = await (first,second)
    await model.load()
    XCTAssertEqual(ClubTestProtocol.reads,1)
    XCTAssertEqual(model.club?.name,"Real fixture club")
    await model.loadMessages()
    XCTAssertEqual(model.messages.first?.id,"message")
    model.drafts["general"] = "Do not leak"
    ClubTestProtocol.revoke()
    await model.load(force:true)
    XCTAssertTrue(model.denied); XCTAssertNil(model.club); XCTAssertTrue(model.messages.isEmpty); XCTAssertTrue(model.drafts.isEmpty)
  }

  func testInviteAndNativeLinkParsingRejectsSpoofedHostsAndCredentials() throws {
    let token=String(repeating:"a",count:64)
    for raw in ["captro://tea-invite/"+token,"https://captro-site.pages.dev/tea-invite/"+token] {
      XCTAssertEqual(CaptroTeaInviteRoute.parse(try XCTUnwrap(URL(string:raw)))?.id,token)
    }
    for raw in ["https://captro-site.pages.dev.evil.example/tea-invite/"+token,"https://user@captro.app/tea-invite/"+token,"https://captro.app/tea-invite/"+token+"?next=evil","captro://tea-invite/bad"] {
      XCTAssertNil(CaptroTeaInviteRoute.parse(try XCTUnwrap(URL(string:raw))))
    }
    XCTAssertEqual(ClubLinkDestination.parse(try XCTUnwrap(CaptroTeaLink("https://captro-site.pages.dev/post/safe_id"))), .post("safe_id"))
    XCTAssertNil(ClubLinkDestination.parse(try XCTUnwrap(CaptroTeaLink("https://captro-site.pages.dev.evil.example/post/safe_id"))))
  }

  @MainActor func testOlderQuoteLoadsBoundedHistoryAndDoesNotJumpOnPolling() async {
    ClubTestProtocol.reset()
    let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[ClubTestProtocol.self]
    let session=URLSession(configuration:config); defer { session.invalidateAndCancel() }
    let model=MIRAAPIClient(session:session)
    let club=model.teaClubs.model("club")
    await club.load(); await club.loadMessages()
    XCTAssertEqual(club.messages.last?.id,"message")
    await club.loadMessages(through:"old-message")
    XCTAssertEqual(club.messages.last?.id,"old-message")
    XCTAssertTrue(club.focusedHistory.contains("general"))
    await club.loadMessages(force:true)
    XCTAssertEqual(club.messages.last?.id,"old-message","A poll must not move the user out of quoted history")
    await club.loadMessages(latest:true)
    XCTAssertEqual(club.messages.last?.id,"message"); XCTAssertFalse(club.focusedHistory.contains("general"))
  }

  func testExistingMessagesDecodeWithoutRoomOrQuoteAndExtractOnlySafeLinks() throws {
    let data=Data(#"{"id":"old","body":"See https://www.youtube.com/watch?v=example and http://example.com","createdAt":"2026-11-14T00:00:00Z","author":{"id":"a","name":"Author","username":"author"}}"#.utf8)
    let message=try JSONDecoder().decode(CaptroClubMessage.self,from:data)
    XCTAssertNil(message.room); XCTAssertNil(message.quote); XCTAssertEqual(message.links.count,1)
    XCTAssertEqual(message.links.first?.hostname,"youtube.com")
  }
}

private final class ClubTestProtocol: URLProtocol {
  private static let lock=NSLock()
  private static var count=0, denied=false
  static var reads: Int { lock.withLock { count } }
  static func reset() { lock.withLock { count=0; denied=false } }
  static func revoke() { lock.withLock { denied=true } }
  override class func canInit(with request:URLRequest)->Bool { true }
  override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
  override func startLoading() {
    let denied=Self.lock.withLock { Self.denied }
    let body:String
    if denied { body=#"{"detail":"Membership revoked"}"# }
    else if request.url!.path.hasSuffix("/messages") {
      let old=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.contains(where:{$0.name=="through"}) == true
      body=#"{"items":[{"id":"message","body":"Member-only text","createdAt":"2026-11-14T00:00:00Z","author":{"id":"a","name":"Author","username":"author"}}]}"#.replacingOccurrences(of:"\"message\"",with:old ? "\"old-message\"" : "\"message\"")
    } else if request.url!.path.hasSuffix("/read") { body="{}" }
    else {
      Self.lock.withLock { Self.count += 1 }
      body=#"{"id":"club","groupId":"group","name":"Real fixture club","role":"member","viewerId":"viewer","memberCount":2,"rules":"","officialLinks":[],"roomsEnabled":false,"version":1,"approvalRequired":false,"rooms":[]}"#
    }
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:denied ? 403:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
    client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
