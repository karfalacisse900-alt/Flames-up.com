#if DEBUG
import SwiftUI

/// Runtime-only test entry. Reads public media, never publishes or edits posts.
public struct CaptroMediaWritingVisualTestView: View {
  @State private var items: [MIRAPickedMedia] = []
  @State private var showEditor = false
  @State private var error: String?
  public init() {}
  public var body: some View {
    VStack {
      if let error { Text(error) }
      else if items.isEmpty { ProgressView() }
      else {
        Text(items.first?.mediaWriting?.text ?? "No media text").accessibilityIdentifier("writing.savedText")
        Button("Edit text on media") { showEditor = true }
      }
    }
    .fullScreenCover(isPresented: $showEditor) {
      CaptroMediaWritingEditor(items: items) { items = $0 }
    }
    .task {
      do {
        let posts: [MIRAPost] = try await MIRAAPIClient().get("/posts/world-board?limit=50&skip=0")
        guard let post = posts.first(where: { $0.id == "7ff613af-f80a-474a-85cc-b159bbcf6a79" }) else { return }
        for url in post.mediaURLs.prefix(2) {
          let (data, response) = try await URLSession.shared.data(from: URL(string: url)!)
          guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
          items.append(MIRAPickedMedia(data: data, kind: .image, fileName: "test-photo.jpg", mimeType: "image/jpeg"))
        }
        showEditor = true
      } catch { self.error = "Test media unavailable" }
    }
  }
}
#endif
