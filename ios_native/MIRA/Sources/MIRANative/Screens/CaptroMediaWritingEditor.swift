import AVKit
import SwiftUI

/// Transactional editor: a local copy is committed only by Done. No export.
struct CaptroMediaWritingEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var items: [MIRAPickedMedia]
  @State private var selected = 0
  @State private var ratios: [CGFloat] = []
  @State private var player: AVPlayer?
  @State private var temporaryVideo: URL?
  @State private var image: UIImage?
  @State private var loadError: String?
  @State private var dragOrigin: CGPoint?
  @State private var guide = false
  @State private var panel = "text"
  @FocusState private var textFocused: Bool
  let onSave: ([MIRAPickedMedia]) -> Void

  init(items: [MIRAPickedMedia], initialIndex: Int = 0, onSave: @escaping ([MIRAPickedMedia]) -> Void) {
    _items = State(initialValue: items)
    _selected = State(initialValue: min(max(0, initialIndex), max(0, items.count - 1)))
    self.onSave = onSave
  }
  private var writing: CaptroMediaWriting {
    get { items[selected].mediaWriting ?? CaptroMediaWriting() }
    nonmutating set {
      var value = newValue
      value.sourceAspectRatio = sourceRatio
      let canvas = CGSize(width: 390, height: 390 * homeRatio)
      let source = value.sourceRect(in: canvas, fill: true)
      value.width = min(value.width, (canvas.width - 24) / source.width)
      let textSize = value.measuredSize(mediaWidth: source.width)
      let minY = (52 - source.minY + textSize.height / 2) / source.height
      let maxY = (canvas.height - 52 - source.minY - textSize.height / 2) / source.height
      if minY <= maxY { value.y = min(maxY, max(minY, value.y)) }
      items[selected].mediaWriting = value
    }
  }
  private var writingBinding: Binding<CaptroMediaWriting> {
    Binding(get: { writing }, set: { writing = $0 })
  }
  private var error: String? {
    items.compactMap { item -> String? in
      guard let value = item.mediaWriting, !value.text.isEmpty else { return nil }
      if let error = value.validationMessage { return error }
      let size = CGSize(width: 390, height: 390 * homeRatio)
      let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
      if !bounds.contains(value.textRect(in: size, fill: true)) { return "The writing extends outside Home’s crop. Move it inward or choose Small." }
      return nil
    }.first
  }
  private var sourceRatio: CGFloat { ratios.indices.contains(selected) ? ratios[selected] : 1 }
  // A carousel has one cover-derived Home canvas, even for mixed source ratios.
  private var homeRatio: CGFloat { MIRAMediaSizing.supportedPostHeightToWidthRatio(1 / (ratios.first ?? 1)) }

  var body: some View {
    NavigationStack {
      GeometryReader { page in
        ScrollView {
          VStack(spacing: 12) {
            if !items.isEmpty {
              let width = min(page.size.width - 32, max(160, (page.size.height - 205) / homeRatio))
              canvas(size: CGSize(width: width, height: width * homeRatio))
              if items.count > 1 {
                HStack {
                  Button { select(selected - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(selected == 0).accessibilityLabel("Previous media")
                  Text("\(selected + 1) of \(items.count)").font(.caption).monospacedDigit()
                  Button { select(selected + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(selected == items.count - 1).accessibilityLabel("Next media")
                }
              }
              Picker("Editing controls", selection: $panel) {
                Text("Text").tag("text"); Text("Style").tag("style")
                Text("Alignment").tag("alignment"); Text("Position").tag("position")
              }.pickerStyle(.segmented)
              controls.disabled(ratios.count != items.count)
              if let message = error {
                Text(message).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("mediaWriting.validation")
              }
              Button("Remove text", role: .destructive) { items[selected].mediaWriting = nil }
                .disabled(writing.text.isEmpty).frame(minHeight: 44)
            }
          }.padding(16)
        }.scrollDismissesKeyboard(.interactively)
      }
      .background(MIRATheme.Color.launchBackground)
      .navigationTitle("").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            for index in items.indices where items[index].mediaWriting?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
              items[index].mediaWriting = nil
            }
            onSave(items); dismiss()
          }.disabled(error != nil || loadError != nil || ratios.count != items.count)
            .accessibilityIdentifier("mediaWriting.done")
        }
      }
      .tint(MIRATheme.Color.forest)
    }
    .task {
      var loaded: [CGFloat] = []
      for item in items {
        let dimension = await item.mediaDimension()
        loaded.append(CGFloat(dimension.originalAspectRatio ?? dimension.ratio ?? 1))
      }
      guard !Task.isCancelled else { return }
      ratios = loaded
    }
    .task(id: selected) { await loadMedia() }
    .onAppear { MIRAPlaybackCoordinator.pauseAll(reason: "media_writing_editor_open") }
    .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
    .onDisappear { cleanup() }
  }

  private func canvas(size: CGSize) -> some View {
    ZStack(alignment: .topLeading) {
      Group {
        if let player { WritingVideoCanvas(player: player) }
        else if let image { Image(uiImage: image).resizable().scaledToFill() }
        else if let loadError { Text(loadError).foregroundStyle(.secondary) }
        else { ProgressView() }
      }.frame(width: size.width, height: size.height).clipped()
      // Advisory preview, not a permanent overlay on published media.
      if items.first?.mediaWriting?.showsStamp != false { Rectangle().fill(.black.opacity(0.08))
        .overlay(alignment: .topLeading) {
          Text("Stamp area").font(.caption2).padding(6).background(.ultraThinMaterial)
        }
        .frame(width: size.width * 0.73, height: size.height * 0.50)
        .offset(x: size.width * 0.054, y: size.height * 0.48)
        .allowsHitTesting(false).accessibilityHidden(true) }
      if !writing.text.isEmpty {
        CaptroMediaWritingLayer(writing: resolvedWriting, container: size)
        let rect = resolvedWriting.textRect(in: size, fill: true)
        Color.clear.frame(width: max(44, rect.width), height: max(44, rect.height))
          .contentShape(Rectangle()).position(x: rect.midX, y: rect.midY)
          .gesture(DragGesture(minimumDistance: 3)
            .onChanged { value in
              textFocused = false
              if dragOrigin == nil { dragOrigin = CGPoint(x: writing.x, y: writing.y) }
              let source = resolvedWriting.sourceRect(in: size, fill: true)
              var x = dragOrigin!.x + value.translation.width / source.width
              let y = dragOrigin!.y + value.translation.height / source.height
              guide = abs(x - 0.5) < 0.025
              if guide { x = 0.5 }
              place(x: x, y: y, canvas: size)
            }.onEnded { _ in dragOrigin = nil; guide = false })
          .accessibilityLabel("Move media text. Use Position controls for precise placement.")
      }
      if guide {
        Rectangle().fill(.white.opacity(0.8)).frame(width: 1, height: size.height)
          .offset(x: size.width / 2).allowsHitTesting(false).accessibilityHidden(true)
      }
      if player != nil {
        Button {
          if let player, player.rate == 0 {
            if let duration = player.currentItem?.duration.seconds, duration.isFinite,
               player.currentTime().seconds >= duration { player.seek(to: .zero) }
            player.play()
          } else { player?.pause() }
        } label: {
          Image(systemName: "playpause.fill").padding(12).background(.ultraThinMaterial, in: Circle())
        }.padding(8).frame(width: size.width, height: size.height, alignment: .bottomTrailing)
          .accessibilityLabel("Play or pause video preview")
      }
    }.frame(width: size.width, height: size.height).clipped()
      .accessibilityIdentifier("mediaWriting.canvas")
  }
  private var resolvedWriting: CaptroMediaWriting {
    var value = writing; value.sourceAspectRatio = sourceRatio; return value
  }
  @ViewBuilder private var controls: some View {
    switch panel {
    case "style":
      Picker("Style", selection: writingBinding.style) {
        Text("Bold").tag("bold"); Text("Clean").tag("clean"); Text("Editorial").tag("editorial")
      }.pickerStyle(.segmented)
      Picker("Size", selection: writingBinding.size) {
        Text("Small").tag("small"); Text("Medium").tag("medium"); Text("Large").tag("large")
      }.pickerStyle(.segmented)
      Picker("Text color", selection: writingBinding.color) {
        Text("White").tag("white"); Text("Black").tag("black")
        Text("Green").tag("green"); Text("Cream").tag("cream")
      }.pickerStyle(.menu)
      Toggle("Readability backing", isOn: writingBinding.readability).font(.subheadline)
    case "alignment":
      Picker("Text alignment", selection: writingBinding.alignment) {
        Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right")
      }.pickerStyle(.segmented)
    case "position":
      if selected == 0 {
        Toggle("Show Captro stamp", isOn: Binding(get: { writing.showsStamp != false }, set: { writing.showsStamp = $0 }))
          .font(.subheadline)
      }
      Text("Drag the writing on the photo, or choose a position. Lower writing may put the stamp below the image.")
        .font(.footnote).foregroundStyle(.secondary)
      HStack {
        Button("Upper") { writing.y = 0.20 }
        Button("Center") { writing.y = 0.5 }
        Button("Lower") { writing.y = 0.75 }
      }.buttonStyle(.bordered)
    default:
      TextField("Your short phrase", text: writingBinding.text, axis: .vertical)
        .lineLimit(1...4).focused($textFocused).font(.body)
        .accessibilityIdentifier("mediaWriting.text")
      Text("\(writing.text.count)/60 · Up to 4 lines").font(.caption).foregroundStyle(.secondary)
    }
  }
  private func place(x: CGFloat, y: CGFloat, canvas: CGSize) {
    var value = resolvedWriting
    let source = value.sourceRect(in: canvas, fill: true)
    let text = value.measuredSize(mediaWidth: source.width)
    let minX = (12 - source.minX + text.width / 2) / source.width
    let maxX = (canvas.width - 12 - source.minX - text.width / 2) / source.width
    let minY = (52 - source.minY + text.height / 2) / source.height
    let maxY = (canvas.height - 52 - source.minY - text.height / 2) / source.height
    value.x = min(maxX, max(minX, x)); value.y = min(maxY, max(minY, y))
    writing = value
  }
  private func select(_ index: Int) {
    guard items.indices.contains(index) else { return }
    textFocused = false; selected = index
  }
  private func cleanup() {
    player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
    if let temporaryVideo { try? FileManager.default.removeItem(at: temporaryVideo) }
    temporaryVideo = nil
  }
  @MainActor private func loadMedia() async {
    cleanup(); image = nil; loadError = nil
    guard items.indices.contains(selected) else { return }
    let item = items[selected]
    if item.kind == .image { image = UIImage(data: item.data); if image == nil { loadError = "This photo could not be opened." }; return }
    do {
      let ext = (item.fileName as NSString).pathExtension
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-writing-\(UUID().uuidString).\(ext.isEmpty ? "mov" : ext)")
      try await Task.detached(priority: .userInitiated) { try item.data.write(to: url, options: .atomic) }.value
      guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
      temporaryVideo = url; player = AVPlayer(url: url)
    } catch { loadError = "This video could not be opened. Try selecting it again." }
  }
}

private struct WritingVideoCanvas: UIViewRepresentable {
  let player: AVPlayer
  func makeUIView(context: Context) -> CanvasView { CanvasView() }
  func updateUIView(_ view: CanvasView, context: Context) { view.playerLayer.player = player }
  static func dismantleUIView(_ view: CanvasView, coordinator: ()) { view.playerLayer.player = nil }
  final class CanvasView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) { super.init(frame: frame); playerLayer.videoGravity = .resizeAspectFill }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
  }
}
