import SwiftUI

/// Uses the same source/crop geometry as Home, without exporting/replacing media.
struct CaptroCoverPreview: View {
  let media: MIRAPickedMedia
  let size: CGSize
  var body: some View {
    let writing = media.mediaWriting ?? .cover()
    let source = writing.sourceRect(in: size, fill: false)
    ZStack(alignment: .topLeading) {
      LocalMediaThumb(media: media, width: source.width, height: source.height, cornerRadius: 0, fitsOriginal: true)
        .offset(x: source.minX, y: source.minY)
      CaptroMediaWritingLayer(writing: writing, container: size, fill: false)
    }.frame(width: size.width, height: size.height).clipped()
  }
}
