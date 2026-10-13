#if DEBUG
import SwiftUI

/// Offline test transport exercises the real store, pager, picker and library.
/// Never installed on the production API client and excluded from Release.
final class CaptroFavoritesReviewProtocol: URLProtocol {
  static var saved = false
  static var revision = 0
  static var memberships: [String] = []
  static var names = ["11111111-1111-4111-8111-111111111111":"Dining", "22222222-2222-4222-8222-222222222222":"New York"]
  override class func canInit(with request:URLRequest)->Bool {request.url?.host == "favorites-review.invalid"}
  override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
  override func startLoading() {
    let path=request.url!.path
    var data=request.httpBody ?? Data()
    if let stream=request.httpBodyStream {
      stream.open(); defer {stream.close()}; var buffer=[UInt8](repeating:0,count:1024)
      while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count); if n<=0 {break}; data.append(buffer,count:n)}
    }
    let body=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
    if request.httpMethod == "PUT",path.contains("/posts/") {
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
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
    client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:result)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

struct CaptroFavoritesReviewHost: View {
  private let api: MIRAAPIClient
  @State private var selected: String?
  @State private var reading = CaptroFeedStampReadingState()
  @State private var opened = false
  init() {
    let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[CaptroFavoritesReviewProtocol.self]
    api=MIRAAPIClient(baseURL:URL(string:"https://favorites-review.invalid")!,sessionProvider:StaticSessionProvider(token:"fixture"),session:URLSession(configuration:config))
    api.favorites.configure(accountID:"review")
  }
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing:0) {
            CaptroFeedPostView(post:CaptroPresentationReviewFixture.post,api:api,isVideoActive:false,showsFeedControls:true,
              onFollow:{false},onOpenOptions:{},onCreate:{},onOpenPost:{opened=true},onSave:{},canFollowAuthor:false,
              feedWidth:geometry.size.width,selectedMediaID:$selected,stampReading:$reading)
            Text("Native review fixture · not a production post").font(.caption).padding()
            NavigationLink("Favorites") {CaptroFavoritesView(api:api)}.padding()
            if opened {Text("Details opened").accessibilityIdentifier("review.details.opened")}
          }
        }.overlay(alignment:.top) {CaptroFavoriteNotice(store:api.favorites)}
      }.navigationTitle("Favorites review").navigationBarTitleDisplayMode(.inline)
    }
  }
}
#endif
