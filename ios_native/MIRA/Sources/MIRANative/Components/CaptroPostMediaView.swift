import SwiftUI

/// Shared by Home, Details and crop preview. One crop transform is applied to
/// the source, its placeholder, video layer, and optional source-relative ink.
struct CaptroPostMediaView: View {
  let url: String
  let geometry: CaptroPostMediaGeometry
  let size: CGSize
  var isVideo = false
  var placeholderURL: String? = nil
  var shouldPlay = false
  var muted = true
  var writing: CaptroMediaWriting? = nil
  var caption: String? = nil
  var maxPixelSize: CGFloat = MIRAMediaSizing.feedTargetHeight

  var body: some View {
    let source = geometry.sourceRect(in: size)
    ZStack(alignment: .topLeading) {
      RemoteMediaView(url: url, isVideo: isVideo, placeholderURL: placeholderURL,
        contentMode: .fill, shouldPlay: shouldPlay, videoMuted: muted,
        maxPixelSize: maxPixelSize,
        placeholderColor: MIRATheme.Color.mediaPlaceholder, plainBackground: true)
        .frame(width: source.width, height: source.height)
        .offset(x: source.minX, y: source.minY)
      if let writing, !writing.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        CaptroMediaWritingLayer(writing: geometry.applying(to: writing), container: size, fill: true, caption: caption)
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .clipped()
  }
}
