#if DEBUG
import SwiftUI
import UIKit

/// Runtime-only test entry. Uses local generated media and never publishes posts.
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
      let size = CGSize(width: 480, height: 600)
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      items = [0, 1].compactMap { index in
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
          (index == 0 ? UIColor.systemTeal : UIColor.systemIndigo).setFill()
          context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        return MIRAPickedMedia(data: data, kind: .image,
          fileName: "media-writing-\(index).jpg", mimeType: "image/jpeg")
      }
      if items.count == 2 { showEditor = true }
      else { error = "Test media unavailable" }
    }
  }
}
#endif
