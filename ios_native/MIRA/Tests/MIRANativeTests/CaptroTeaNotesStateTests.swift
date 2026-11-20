import XCTest
@testable import MIRANative

@MainActor final class CaptroTeaNotesStateTests: XCTestCase {
  private func client() -> (MIRAAPIClient, URLSession) {
    NotesStateProtocol.reset()
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NotesStateProtocol.self]
    let session = URLSession(configuration: config)
    return (MIRAAPIClient(session: session), session)
  }
  func testPagedRefreshIsAtomicKeepsTailAndDeduplicatesConcurrentReaders() async throws {
    let (api, session) = client(); defer { session.invalidateAndCancel() }
    api.teaConversations.saveListing((1...40).map(NotesStateProtocol.note), cursor: "old40", receivedAt: Date().addingTimeInterval(-700))
    XCTAssertEqual(api.teaConversations.cachedListing()?.items.count, 40, "Age must not erase presentable content")
    let model = api.teaConversations.notesList()
    let refresh = Task { await model.load(reset: true) }
    await Task.yield()
    XCTAssertEqual(model.items.count, 40, "Keep pages visible while refreshing")
    async let duplicate: Void = model.load(reset: true)
    await refresh.value; await duplicate
    XCTAssertEqual(model.items.first?.id, "0")
    XCTAssertTrue(model.items.contains { $0.id == "40" }, "New first-page insertions must not discard the old tail")
    XCTAssertEqual(Set(model.items.map(\.id)).count, model.items.count)
    XCTAssertEqual(NotesStateProtocol.counts().list, 3)
    await model.load(reset: true)
    XCTAssertEqual(NotesStateProtocol.counts().list, 3, "Fresh repeat/tab/resume shares the existing list")
    XCTAssertTrue(model === api.teaConversations.notesList())
  }
  func testOfflineLaterPageLeavesAllCachedRowsAndCursorThenRecovers() async throws {
    let (api, session) = client(); defer { session.invalidateAndCancel() }
    api.teaConversations.saveListing((1...40).map(NotesStateProtocol.note), cursor: "old40", receivedAt: Date().addingTimeInterval(-700))
    let model = api.teaConversations.notesList()
    NotesStateProtocol.setFailure(true)
    await model.load(reset: true)
    XCTAssertEqual(model.items.map(\.id), (1...40).map(String.init)); XCTAssertEqual(model.nextCursor, "old40")
    XCTAssertNotNil(model.error)
    NotesStateProtocol.setFailure(false)
    await model.retry()
    XCTAssertNil(model.error); XCTAssertTrue(model.items.contains { $0.id == "40" })
    XCTAssertEqual(model.items.first?.id,"0", "Retry must refresh the head, not append the next page")
  }
  func testInterestUndoSharedStateNoDuplicateTapsAndStaleReadCannotOverwriteWrite() async throws {
    let (api, session) = client(); defer { session.invalidateAndCancel() }
    let note = NotesStateProtocol.note(1), started = Date()
    let first = api.teaConversations.signal(for: note)
    XCTAssertTrue(first === api.teaConversations.signal(for: note))
    async let a: Void = first.choose("interested")
    async let b: Void = first.choose("interested")
    _ = await (a,b)
    XCTAssertEqual(first.interest,"interested"); XCTAssertEqual(NotesStateProtocol.counts().writes,1)
    XCTAssertEqual(first.engagementCount,1)
    first.hydrate(nil,readStartedAt: started); XCTAssertEqual(first.interest,"interested")
    await first.choose("pass"); XCTAssertEqual(first.interest,"pass")
    XCTAssertEqual(first.engagementCount,0)
    await first.choose("pass"); XCTAssertNil(first.interest)
    XCTAssertEqual(NotesStateProtocol.counts().choices,["interested","pass","null"])
  }
  func testOpensOnlyFromDetailAndAccountSwitchErasesPrivateStateDraftsAndPages() async throws {
    MIRALocalJSONCache.setAccountScope(userId:"notes-a")
    defer { MIRALocalJSONCache.setAccountScope(userId:nil) }
    let (api, session) = client(); defer { session.invalidateAndCancel() }
    let note = NotesStateProtocol.note(1)
    let signal = api.teaConversations.signal(for:note)
    let list = api.teaConversations.notesList()
    await list.load(reset:true)
    XCTAssertEqual(NotesStateProtocol.counts().opens,0)
    await signal.qualifyRead(isAuthor:false,authenticated:true,wait: { _ in })
    await signal.qualifyRead(isAuthor:false,authenticated:true,wait: { _ in })
    XCTAssertEqual(NotesStateProtocol.counts().opens,1)
    await signal.choose("interested")
    let detail = api.teaConversations.model(for:note); detail.draft="Half written reply"
    MIRALocalJSONCache.setAccountScope(userId:"notes-b")
    _ = api.teaConversations.notesList()
    XCTAssertTrue(list.items.isEmpty); XCTAssertNil(signal.interest); XCTAssertFalse(signal.valid)
    XCTAssertEqual(detail.draft,""); XCTAssertNil(detail.post)
  }
  func testUncertainInterestRetryRepeatsAbsoluteIntentInsteadOfTogglingTwice() async throws {
    let (api,session) = client(); defer { session.invalidateAndCancel() }
    let signal = api.teaConversations.signal(for:NotesStateProtocol.note(1))
    NotesStateProtocol.loseNextAcknowledgment()
    await signal.choose("interested")
    XCTAssertNil(signal.interest); XCTAssertNotNil(signal.error)
    await signal.choose("interested")
    XCTAssertEqual(signal.interest,"interested"); XCTAssertNil(signal.error)
    XCTAssertEqual(NotesStateProtocol.counts().choices,["interested","interested"])
    await signal.choose("interested"); XCTAssertNil(signal.interest)
  }
  func testFourSecondsAndBackgroundResetDoNotAccumulateButFiveContinuousSecondsQualify() async throws {
    let (api,session)=client(); defer { session.invalidateAndCancel() }
    let signal=api.teaConversations.signal(for:NotesStateProtocol.note(1))
    let quick=Task { await signal.qualifyRead(isAuthor:false,authenticated:true) }
    try await Task.sleep(nanoseconds:4_000_000_000)
    XCTAssertEqual(NotesStateProtocol.counts().opens,0)
    quick.cancel(); await quick.value
    // The detail's scenePhase task is cancelled on inactive/background and a
    // fresh task begins on return. Four seconds cannot carry into that task.
    let resumed=Task { await signal.qualifyRead(isAuthor:false,authenticated:true) }
    try await Task.sleep(nanoseconds:4_000_000_000)
    XCTAssertEqual(NotesStateProtocol.counts().opens,0)
    await resumed.value
    XCTAssertEqual(NotesStateProtocol.counts().starts,2)
    XCTAssertEqual(NotesStateProtocol.counts().opens,1)
    XCTAssertEqual(signal.engagementCount,1)
    await signal.qualifyRead(isAuthor:false,authenticated:true)
    XCTAssertEqual(NotesStateProtocol.counts().starts,2,"Qualified revisit needs no new read request")
    await signal.choose("interested"); await signal.choose("pass")
    XCTAssertEqual(signal.engagementCount,1,"The server's qualified-read union survives removing plus")
  }
  func testGuestDoesNotStartReadAndOldCountResponseCannotOverwriteNewerOne() async throws {
    let (api,session)=client(); defer { session.invalidateAndCancel() }
    let signal=api.teaConversations.signal(for:NotesStateProtocol.note(1))
    await signal.qualifyRead(isAuthor:false,authenticated:false)
    XCTAssertEqual(NotesStateProtocol.counts().starts,0)
    signal.acceptEngagement(12,at:"2026-11-20T10:00:01.000Z")
    signal.acceptEngagement(9,at:"2026-11-20T10:00:00.000Z")
    XCTAssertEqual(signal.engagementCount,12)
    signal.acceptEngagement(10,at:"2026-11-20T10:00:02.000Z")
    XCTAssertEqual(signal.engagementCount,10,"A newer removal must be allowed to lower the count")
  }
}

private final class NotesStateProtocol: URLProtocol, @unchecked Sendable {
  struct Counts { var list=0; var writes=0; var opens=0; var starts=0; var choices:[String]=[] }
  private static let lock=NSLock()
  private static var state=Counts()
  private static var fail=false
  private static var loseAcknowledgment=false
  private var delivery: DispatchWorkItem?
  static func reset() { lock.withLock { state=Counts(); fail=false; loseAcknowledgment=false } }
  static func loseNextAcknowledgment() { lock.withLock { loseAcknowledgment=true } }
  static func counts() -> Counts { lock.withLock { state } }
  static func setFailure(_ value:Bool) { lock.withLock { fail=value } }
  static func note(_ number:Int) -> CaptroTeaConversation {
    CaptroTeaConversation(id:String(number),title:"Note \(number)",body:"A real-shaped fixture caption.",links:[],
      author:CaptroTeaAuthor(id:"author",name:"Author",username:"author"),createdAt:"2026-11-19T12:00:00Z",version:1,isAuthor:false,following:false)
  }
  override class func canInit(with request:URLRequest)->Bool { true }
  override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
  override func startLoading() {
    let url=request.url!, path=url.path
    var data=Data(), status=200
    if path.hasSuffix("/interest") {
      var bytes=request.httpBody ?? Data()
      if bytes.isEmpty,let stream=request.httpBodyStream {
        stream.open(); defer { stream.close() }; var buffer=[UInt8](repeating:0,count:1024)
        while stream.hasBytesAvailable { let count=stream.read(&buffer,maxLength:buffer.count); if count<=0 { break }; bytes.append(buffer,count:count) }
      }
      let value=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] ?? [:]
      let choice=value["interest"] as? String
      Self.lock.withLock { Self.state.writes+=1; Self.state.choices.append(choice ?? "null") }
      data=try! JSONSerialization.data(withJSONObject:["interest":choice as Any? ?? NSNull(),"engagementCount":choice == "interested" || Self.counts().opens > 0 ? 1 : 0])
      if Self.lock.withLock({ let lose=Self.loseAcknowledgment; Self.loseAcknowledgment=false; return lose }) {
        status=503; data=Data(#"{"detail":"Lost acknowledgment"}"#.utf8)
      }
    } else if path.hasSuffix("/read-start") {
      Self.lock.withLock { Self.state.starts+=1 }; data=Data(#"{"qualified":false,"token":"read-token","engagementCount":0}"#.utf8)
    } else if path.hasSuffix("/read-qualify") {
      Self.lock.withLock { Self.state.opens+=1 }; data=Data(#"{"qualified":true,"engagementCount":1}"#.utf8)
    } else {
      Self.lock.withLock { Self.state.list+=1 }
      let cursor=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first?.value
      let offset=Int(cursor ?? "0") ?? 0
      if offset>0 && Self.lock.withLock({ Self.fail }) { status=503; data=Data(#"{"detail":"Offline"}"#.utf8) }
      else {
        let notes=(offset..<min(60,offset+20)).map(Self.note)
        let rows=try! JSONSerialization.jsonObject(with:JSONEncoder().encode(notes))
        data=try! JSONSerialization.data(withJSONObject:["items":rows,"nextCursor":offset<40 ? String(offset+20) as Any : NSNull()])
      }
    }
    let response=HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
    let bytes=data
    let item=DispatchWorkItem { [weak self] in
      guard let self else { return }; self.client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
      self.client?.urlProtocol(self,didLoad:bytes); self.client?.urlProtocolDidFinishLoading(self)
    }
    delivery=item; DispatchQueue.global().asyncAfter(deadline:.now()+0.05,execute:item)
  }
  override func stopLoading() { delivery?.cancel() }
}
