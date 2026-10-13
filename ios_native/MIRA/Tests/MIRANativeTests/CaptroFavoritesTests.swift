import XCTest
@testable import MIRANative

@MainActor final class CaptroFavoritesTests: XCTestCase {
  private func client() -> MIRAAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FavoritesTestProtocol.self]
    let api = MIRAAPIClient(baseURL: URL(string: "https://localhost:9443")!, sessionProvider: StaticSessionProvider(token: "fixture"), session: URLSession(configuration: config))
    api.favorites.configure(accountID: "alice")
    return api
  }
  private func response(_ saved: Bool, _ revision: Int, _ ids: [String] = []) -> Data {
    try! JSONSerialization.data(withJSONObject: ["state": ["post_id":"post", "saved":saved,"revision":revision,"collection_ids":ids],"collections":[]])
  }
  func testSaveUnsaveUndoRestoresMembershipsAndNoLikeRequest() async throws {
    let api=client(), store=api.favorites
    var saved=true, revision=1, ids=["collection-a","collection-b"], writes=0
    FavoritesTestProtocol.reply = { request in
      XCTAssertEqual(request.url?.path,"/favorites/posts/post")
      if request.httpMethod == "PUT" {
        let body=try! JSONSerialization.jsonObject(with: FavoritesTestProtocol.body(request)) as! [String:Any]
        saved=body["saved"] as! Bool; ids=body["collection_ids"] as! [String]; revision += 1; writes += 1
      }
      return (200, self.response(saved,revision,ids),0)
    }
    let original=try await store.loadState(postID:"post")
    await store.remove(state: original)
    XCTAssertEqual(store.states["post"]?.saved,false)
    XCTAssertEqual(store.noticeAction,"Undo")
    await store.runNoticeAction()
    XCTAssertEqual(store.states["post"]?.collectionIds,["collection-a","collection-b"])
    XCTAssertEqual(writes,2)
  }
  func testPickerReadDoesNotSaveAndFailureRollsBackWithRetry() async throws {
    let api=client(), store=api.favorites
    var writes=0
    FavoritesTestProtocol.reply = { request in
      if request.httpMethod == "PUT" { writes += 1; return (503,Data("{\"detail\":\"Offline\"}".utf8),0) }
      return (200,self.response(false,0),0)
    }
    let original=try await store.loadState(postID:"post")
    XCTAssertEqual(writes,0)
    let success=await store.organize(previous:original,collectionIDs:[])
    XCTAssertFalse(success); XCTAssertEqual(store.states["post"]?.saved,false)
    XCTAssertTrue(store.busy.isEmpty); XCTAssertEqual(store.noticeAction,"Retry")
  }
  func testLateReadCannotOverwriteSave() async throws {
    let api=client(), store=api.favorites
    FavoritesTestProtocol.reply = { request in
      request.httpMethod == "PUT" ? (200,self.response(true,1),0) : (200,self.response(false,0),0.2)
    }
    let read=Task { try await store.loadState(postID:"post") }
    await Task.yield()
    try await Task.sleep(for:.milliseconds(30))
    let saved=await store.organize(previous:.init(postId:"post",saved:false,revision:0,collectionIds:[]),collectionIDs:[])
    XCTAssertTrue(saved)
    do { _ = try await read.value; XCTFail("Obsolete read accepted") } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(store.states["post"]?.saved,true)
  }
  func testAccountSwitchRejectsInflightResponse() async throws {
    let api=client(),store=api.favorites
    FavoritesTestProtocol.reply = { _ in (200,self.response(true,1,["private"]),0.2) }
    let read=Task {try await store.loadState(postID:"post")}
    try await Task.sleep(for:.milliseconds(30))
    store.configure(accountID:"bob")
    do {_ = try await read.value; XCTFail("Old account accepted")} catch {}
    XCTAssertTrue(store.states.isEmpty); XCTAssertTrue(store.collections.isEmpty)
    store.configure(accountID:""); XCTAssertFalse(store.requireAccount())
  }
}
private final class FavoritesTestProtocol: URLProtocol {
  static var reply: ((URLRequest)->(Int,Data,Double))!
  override class func canInit(with request: URLRequest)->Bool {request.url?.host == "localhost" && request.url?.port == 9443}
  override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
  static func body(_ request:URLRequest)->Data {
    if let data=request.httpBody {return data}
    guard let stream=request.httpBodyStream else {return Data()}
    stream.open(); defer {stream.close()}; var result=Data(); var bytes=[UInt8](repeating:0,count:1024)
    while stream.hasBytesAvailable {let n=stream.read(&bytes,maxLength:bytes.count); if n<=0 {break}; result.append(bytes,count:n)}
    return result
  }
  override func startLoading() {
    let (status,data,delay)=Self.reply(request)
    DispatchQueue.global().asyncAfter(deadline:.now()+delay) { [self] in
      client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
      client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {}
}
