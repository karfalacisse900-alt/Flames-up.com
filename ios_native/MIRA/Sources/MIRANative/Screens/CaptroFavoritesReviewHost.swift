#if DEBUG
import SwiftUI

/// Offline test transport exercises the real store, pager, picker and library.
/// Never installed on the production API client and excluded from Release.
final class CaptroFavoritesReviewProtocol: URLProtocol {
  static var saved = false
  static var revision = 0
  static var memberships: [String] = []
  static var failedOnce = false
  static var comments: [[String: Any]] = []
  static var names = ["11111111-1111-4111-8111-111111111111":"Dining", "22222222-2222-4222-8222-222222222222":"New York"]
  override class func canInit(with request:URLRequest)->Bool {request.url?.host == "localhost" && request.url?.port == 9444}
  override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
  override func startLoading() {
    let path=request.url!.path
    var data=request.httpBody ?? Data()
    if let stream=request.httpBodyStream {
      stream.open(); defer {stream.close()}; var buffer=[UInt8](repeating:0,count:1024)
      while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count); if n<=0 {break}; data.append(buffer,count:n)}
    }
    let body=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
    if path == "/auth/me" { respond(["id": "review", "username": "review"]); return }
    if path == "/posts/review-post" {
      var post = CaptroPresentationReviewFixture.postRecord; post["savedByMe"] = Self.saved
      respond(post); return
    }
    if path == "/posts/review-post/comments" {
      if request.httpMethod == "POST" {
        let comment: [String: Any] = ["id": UUID().uuidString, "postId": "review-post", "userId": "review",
          "content": body["content"] ?? "", "createdAt": "2026-10-16T14:00:00Z"]
        Self.comments.append(comment); respond(comment)
      } else { respond(Self.comments) }
      return
    }
    if request.httpMethod == "PUT",path.contains("/posts/") {
      if ProcessInfo.processInfo.arguments.contains("--favorites-fail-once"), !Self.failedOnce {
        Self.failedOnce = true; respond(["detail": "Offline fixture"], status: 503, delay: 0.5); return
      }
      Self.saved=body["saved"] as? Bool ?? false
      Self.memberships=body["collection_ids"] as? [String] ?? []
      Self.revision += 1
    } else if request.httpMethod == "POST" {Self.names[UUID().uuidString]=body["name"] as? String ?? "Collection"}
    else if request.httpMethod == "DELETE" {Self.names.removeValue(forKey:request.url!.lastPathComponent)}
    else if request.httpMethod == "PUT" {Self.names[request.url!.lastPathComponent]=body["name"] as? String}
    let collections=Self.names.sorted{$0.value<$1.value}.map { id,name -> [String:Any] in
      ["id":id,"name":name,"count":Self.memberships.contains(id) ? 1:0,"previews":[]]
    }
    var result:[String:Any]=["state":["post_id":"review-post","saved":Self.saved,"revision":Self.revision,"collection_ids":Self.memberships],"collections":collections]
    if path == "/favorites" {
      result["entries"]=Self.saved ? [["id":"review-post","post":CaptroPresentationReviewFixture.postRecord]]:[]
      result["has_more"]=false; result["next_offset"]=Self.saved ? 1:0
    }
    respond(result, delay: ProcessInfo.processInfo.arguments.contains("--favorites-delayed") ? 0.5 : 0)
  }
  private func respond(_ value: Any, status: Int = 200, delay: TimeInterval = 0) {
    let data = try! JSONSerialization.data(withJSONObject: value)
    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
      client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
      client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {}
}

struct CaptroFavoritesReviewHost: View {
  private let api: MIRAAPIClient
  @StateObject private var rowState = CaptroFeedRowState()
  @State private var opened = false
  init() {
    let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[CaptroFavoritesReviewProtocol.self]
    api=MIRAAPIClient(baseURL:URL(string:"https://localhost:9444")!,sessionProvider:StaticSessionProvider(token:"fixture"),session:URLSession(configuration:config))
    api.favorites.configure(accountID:"review")
  }
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing:0) {
            CaptroFeedPostView(post:CaptroPresentationReviewFixture.post,api:api,isVideoActive:!opened,showsFeedControls:true,
              onFollow:{false},onOpenOptions:{},onCreate:{},onOpenPost:{opened=true},onSave:{},canFollowAuthor:false,
              feedWidth:geometry.size.width,rowState:rowState)
            Text("Native review fixture · not a production post").font(.caption).padding()
            NavigationLink("Favorites") {CaptroFavoritesView(api:api)}.padding()
            if opened {Text("Details opened").accessibilityIdentifier("review.details.opened")}
          }
        }.overlay(alignment:.top) {CaptroFavoriteNotice(store:api.favorites)}
      }.navigationTitle("Favorites review").navigationBarTitleDisplayMode(.inline)
      .navigationDestination(isPresented: $opened) {
        PostDetailNativeView(post: CaptroPresentationReviewFixture.post, api: api)
      }
    }
  }
}
#endif
