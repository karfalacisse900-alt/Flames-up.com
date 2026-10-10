import SwiftUI
import UIKit

/// Opens the stored media references fitted to the device. Zoom is opt-in and
/// never changes the underlying asset or the post's feed presentation.
struct CaptroFullscreenMediaViewer: View {
  let urls: [String]
  let post: MIRAPost
  @Environment(\.dismiss) private var dismiss
  @State private var selectedIndex: Int

  init(urls: [String], post: MIRAPost, initialIndex: Int) {
    self.urls = urls
    self.post = post
    _selectedIndex = State(initialValue: min(max(initialIndex, 0), max(urls.count - 1, 0)))
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        MIRATheme.Color.mediaPlaceholder.ignoresSafeArea()
        TabView(selection: $selectedIndex) {
          ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
            CaptroZoomableMedia(
              url: url,
              isVideo: url.isVideoURL,
              isActive: selectedIndex == index,
              size: geometry.size
            )
            .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
      }
      .safeAreaInset(edge: .top) {
        HStack {
          Button("Close") { dismiss() }
            .frame(minWidth: 44, minHeight: 44)
          Spacer()
          if urls.count > 1 {
            Text("\(selectedIndex + 1) / \(urls.count)")
              .font(.caption.monospacedDigit())
          }
        }
        .padding(.horizontal, 16)
        .background(MIRATheme.Color.surface.opacity(0.94))
      }
    }
    .accessibilityLabel("Full media viewer")
  }
}

private struct CaptroZoomableMedia: View {
  let url: String
  let isVideo: Bool
  let isActive: Bool
  let size: CGSize
  @State private var scale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @GestureState private var pinching: CGFloat = 1
  @GestureState private var dragging: CGSize = .zero

  var body: some View {
    RemoteMediaView(
      url: url,
      isVideo: isVideo,
      contentMode: .fit,
      shouldPlay: isVideo && isActive,
      maxPixelSize: max(size.width, size.height) * UIScreen.main.scale,
      placeholderColor: MIRATheme.Color.mediaPlaceholder,
      plainBackground: true
    )
    .frame(width: size.width, height: size.height)
    .scaleEffect(isVideo ? 1 : min(4, max(1, scale * pinching)))
    .offset(x: offset.width + dragging.width, y: offset.height + dragging.height)
    .simultaneousGesture(MagnificationGesture()
      .updating($pinching) { value, state, _ in if !isVideo { state = value } }
      .onEnded { value in
        guard !isVideo else { return }
        scale = min(4, max(1, scale * value))
        if scale == 1 { offset = .zero }
      })
    .simultaneousGesture(DragGesture()
      .updating($dragging) { value, state, _ in
        if !isVideo && scale > 1 { state = value.translation }
      }
      .onEnded { value in
        guard !isVideo && scale > 1 else { return }
        offset.width += value.translation.width
        offset.height += value.translation.height
      })
    .onTapGesture(count: 2) {
      guard !isVideo else { return }
      scale = 1
      offset = .zero
    }
    .accessibilityHint(isVideo ? "Video plays in its complete frame" : "Pinch to zoom, drag to pan, or double-tap to reset")
  }
}
