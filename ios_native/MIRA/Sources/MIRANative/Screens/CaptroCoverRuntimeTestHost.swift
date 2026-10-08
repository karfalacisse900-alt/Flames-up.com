#if DEBUG
import SwiftUI

/// Private, real-backend simulator acceptance harness. No mock success or
/// synthetic published records. Credentials are provisioned by protected CI,
/// never bundled, logged, or included in screenshot artifacts.
struct CaptroCoverRuntimeTestHost: View {
  private struct Session: Decodable { let token: String; let userID: String }
  @State private var api: MIRAAPIClient?
  @State private var media: MIRAPickedMedia?
  @State private var additionalMedia: [MIRAPickedMedia] = []
  @State private var userID = ""
  @State private var feed: MainFeedModel?
  @State private var error: String?
  @State private var ready = false

  var body: some View {
    Group {
      if let feed, let api {
        TabView {
          MainFeedView(api: api, model: feed).tabItem { Label("Home", systemImage: "house") }
          Text("Capture").tabItem { Label("Capture", systemImage: "doc.viewfinder") }
          Text("Me").tabItem { Label("Me", systemImage: "person") }
        }
      } else if ready, let api {
        CreatePostNativeView(api: api, initialMedia: media, initialAdditionalMedia: additionalMedia,
          onClose: { Task { await readPublishedPost() } })
      } else if let error { Text(error).accessibilityIdentifier("cover.runtime.error") }
      else { ProgressView() }
    }
    .task {
      do {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: folder.appendingPathComponent("cover-session.json")))
        let client = MIRAAPIClient(sessionProvider: StaticSessionProvider(token: session.token))
        let _: MIRAUser = try await client.get("/auth/me")
        userID = session.userID; api = client
        let file = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--cover-file=") }?.dropFirst("--cover-file=".count) ?? "fashion.jpg"
        if file != "picker" {
          let name = file == "carousel" ? "fashion.jpg" : String(file)
          media = MIRAPickedMedia(data: try Data(contentsOf: folder.appendingPathComponent(name)),
            kind: name.hasSuffix(".mp4") ? .video : .image, fileName: name,
            mimeType: name.hasSuffix(".mp4") ? "video/mp4" : "image/jpeg")
          if file == "carousel" {
            let second = "dining.jpg"
            additionalMedia = [MIRAPickedMedia(data: try Data(contentsOf: folder.appendingPathComponent(second)),
              kind: .image, fileName: second, mimeType: "image/jpeg")]
          }
        }
        await MIRAAppCacheStore.shared.clearPostDraft()
        UserDefaults.standard.set("private", forKey: "captro.composer.audience.\(session.userID)")
        ready = true
      } catch { self.error = "Private Cover test setup failed." }
    }
  }

  @MainActor private func readPublishedPost() async {
    guard let api else { return }
    do {
      let posts: [MIRAPost] = try await api.get("/users/\(userID)/posts")
      guard !posts.isEmpty else { error = "No published private post was returned."; ready = false; return }
      feed = MainFeedModel(api: api, visualPosts: posts)
    } catch { self.error = "Could not read the published private Cover."; ready = false }
  }
}
#endif
