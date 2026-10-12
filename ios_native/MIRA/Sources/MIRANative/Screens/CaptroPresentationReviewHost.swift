#if DEBUG
import SwiftUI
import ImageIO

/// Native-screen review fixtures only. No production records or payments are
/// created. The simulator workflow supplies a photograph in Documents.
enum CaptroPresentationReviewFixture {
  static var kind: String {
    ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--review-kind=") }?
      .components(separatedBy: "=").last ?? "general"
  }
  static var mediaURL: String {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("presentation-photo.jpg").absoluteString
  }
  static let dimensions: [String: Int] = {
    guard let url = URL(string: mediaURL),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      preconditionFailure("Review photograph must be installed before launching")
    }
    let rotated = [5, 6, 7, 8].contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
    return ["width": rotated ? height : width, "height": rotated ? width : height]
  }()
  static var postRecord: [String: Any] {
    var value: [String: Any] = [
      "id": "review-post", "userId": "review-author", "userUsername": "captro_test",
      "postType": kind, "title": kind == "general" ? "" : "Neighborhood \(kind.capitalized)",
      "caption": "An afternoon around the neighborhood. Full captions remain readable here, with room for the details that matter.",
      "displayCity": "New York", "createdAt": "2026-10-12T14:00:00Z",
      "image": mediaURL, "images": [mediaURL], "feedMediaUrls": [mediaURL],
      "mediaDimensions": [dimensions],
      "likesCount": 12, "commentsCount": 0,
      "response": ["type": "yes_no", "options": ["Yes", "No"], "counts": ["Yes": 2], "totalCount": 2]
    ]
    if let commerce = commerceRecord { value["detail"] = ["commerce": commerce] }
    return value
  }
  static var commerceRecord: [String: Any]? {
    let fulfillment = ["club": "membership", "group": "group_access", "meetup": "attendance",
      "event": "ticket", "party": "ticket", "ticket": "ticket", "booking": "reservation",
      "deal": "redemption", "local_offer": "redemption"]
    guard let delivery = fulfillment[kind] else { return nil }
    let paid = ProcessInfo.processInfo.arguments.contains("--review-paid")
    var value: [String: Any] = [
      "id": "review-commerce", "postId": "review-post",
      "contentType": kind == "local_offer" ? "offer" : kind,
      "fulfillmentType": delivery, "paymentModel": paid ? "paid" : "free",
      "commerceClass": "physical", "title": "Neighborhood \(kind.capitalized)",
      "description": "Test stamp terms. Access is granted only after server confirmation.",
      "locationName": "Manhattan", "joinedCount": 0, "refundPolicy": "",
      "approvalRequired": false, "passRequired": delivery == "ticket",
      "status": "active", "audience": "anyone",
      "prices": [["id": "review-price", "label": "Standard", "unitAmount": paid ? 1500 : 0,
        "currency": "USD", "billingPeriod": "one_time", "active": true]]
    ]
    if ProcessInfo.processInfo.arguments.contains("--review-unavailable") { value["status"] = "expired" }
    if ProcessInfo.processInfo.arguments.contains("--review-joined") {
      value["viewerStatus"] = "active"
      value["viewerDestinationId"] = "review-group"
    }
    return value
  }
  static var post: MIRAPost {
    try! JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject: postRecord))
  }
  static var group: MIRAStoryGroup {
    var story: [String: Any] = [
      "id": "review-story", "userId": "review-author", "image": mediaURL,
      "createdAt": "2026-10-12T14:00:00Z", "locationName": "Manhattan",
      "content": "A quiet afternoon", "likesCount": 0, "likedByMe": false
    ]
    if kind != "general" {
      story["linkedItem"] = ["type": kind, "id": "review-attachment",
        "postId": "review-post", "title": "Neighborhood \(kind.capitalized)"]
    }
    return try! JSONDecoder().decode(MIRAStoryGroup.self, from: JSONSerialization.data(withJSONObject: [
      "userId": "review-author", "userFullName": "Test Creator", "userUsername": "captro_test", "statuses": [story]
    ]))
  }
}

struct CaptroPresentationReviewHost: View {
  @State private var showsStory = false
  private let api = CaptroComposerTestAPI.make()
  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text("Native UI review · test content").font(.headline)
        NavigationLink("Open Details") { PostDetailNativeView(post: CaptroPresentationReviewFixture.post, api: api) }
        Button("Open Story") { showsStory = true }
      }
      .fullScreenCover(isPresented: $showsStory) {
        StoryViewerNativeView(group: CaptroPresentationReviewFixture.group,
          allGroups: [CaptroPresentationReviewFixture.group], api: api,
          onClose: { showsStory = false }, onReportStory: { _ in },
          onOpenLinkedPost: { _ in showsStory = false })
      }
    }
  }
}
#endif
