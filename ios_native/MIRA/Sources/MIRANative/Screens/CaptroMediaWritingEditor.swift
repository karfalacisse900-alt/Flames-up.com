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
  @State private var adjustsCrop = false
  @State private var cropOrigin: CGPoint?
  @State private var automaticallySizedCoverIndices: Set<Int>
  @State private var didFocusCoverHeadline = false
  @FocusState private var textFocused: Bool
  let coverMode: Bool
  let onSave: ([MIRAPickedMedia]) -> Void

  init(items: [MIRAPickedMedia], initialIndex: Int = 0, coverMode: Bool = false, onSave: @escaping ([MIRAPickedMedia]) -> Void) {
    self.coverMode = coverMode
    _automaticallySizedCoverIndices = State(initialValue: Set(items.indices.filter { coverMode && items[$0].mediaWriting?.schemaVersion != 2 }))
    _items = State(initialValue: items.map { item in
      guard coverMode else { return item }
      var item = item
      var writing: CaptroMediaWriting
      if let existing = item.mediaWriting, existing.schemaVersion == 2 {
        writing = existing // Existing published/draft artwork is never restyled implicitly.
      } else {
        writing = .cover()
        writing.text = item.mediaWriting?.text ?? ""
      }
      item.mediaWriting = writing; return item
    })
    _selected = State(initialValue: min(max(0, initialIndex), max(0, items.count - 1)))
    self.onSave = onSave
  }
  private var writing: CaptroMediaWriting {
    get { items[selected].mediaWriting ?? (coverMode ? .cover() : CaptroMediaWriting()) }
    nonmutating set {
      var value = newValue
      value.sourceAspectRatio = sourceRatio
      let canvas = CGSize(width: 1000, height: 1000 * homeRatio)
      let source = value.sourceRect(in: canvas, fill: true)
      value.width = min(value.width, (canvas.width * 0.92) / source.width)
      items[selected].mediaWriting = value
    }
  }
  private var writingBinding: Binding<CaptroMediaWriting> {
    Binding(get: { writing }, set: { writing = $0 })
  }
  private var coverTextBinding: Binding<String> {
    Binding(get: { writing.text.uppercased() }, set: {
      var value = writing
      value.text = $0.uppercased()
      writing = value
    })
  }
  private var error: String? {
    if coverMode && items.first?.mediaWriting?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      return "Write a short headline for the first photo or video."
    }
    return items.enumerated().compactMap { index, item -> String? in
      guard let stored = item.mediaWriting, !stored.text.isEmpty else { return nil }
      var value = stored
      if let error = value.validationMessage { return error }
      if ratios.indices.contains(index) { value.sourceAspectRatio = ratios[index] }
      let size = CGSize(width: 1000, height: 1000 * homeRatio)
      let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 26, dy: 26)
      if !bounds.contains(value.textRect(in: size, fill: true)) { return "The writing extends outside Home’s crop. Move it inward or choose Small." }
      return nil
    }.first
  }
  private var sourceRatio: CGFloat { ratios.indices.contains(selected) ? ratios[selected] : 1 }
  // A carousel has one cover-derived Home canvas, even for mixed source ratios.
  private var homeRatio: CGFloat {
    if let ratio = items.first?.mediaWriting?.homeAspectRatio { return 1 / ratio }
    return MIRAMediaSizing.homeDisplayRatio(1 / (ratios.first ?? 1))
  }

  var body: some View {
    NavigationStack {
      GeometryReader { page in
        ScrollView {
          VStack(spacing: 12) {
            if !items.isEmpty {
              let width = min(page.size.width - 32, max(160, (page.size.height - (coverMode ? 96 : 205)) / homeRatio))
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
              if !coverMode {
                Picker("Editing controls", selection: $panel) {
                  Text("Text").tag("text"); Text("Style").tag("style")
                  Text("Alignment").tag("alignment"); Text("Position").tag("position")
                }.pickerStyle(.segmented)
                controls.disabled(ratios.count != items.count)
                Button("Remove text", role: .destructive) { items[selected].mediaWriting = nil }
                  .disabled(writing.text.isEmpty).frame(minHeight: 44)
              }
              if let message = error, !writing.text.isEmpty {
                Text(message).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("mediaWriting.validation")
              }
            }
          }.padding(16)
        }.scrollDismissesKeyboard(.interactively)
      }
      .background(MIRATheme.Color.launchBackground)
      .navigationTitle(coverMode ? "Cover" : "").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            textFocused = false
            for index in items.indices where !coverMode && items[index].mediaWriting?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
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
      let resolvedHomeRatio = MIRAMediaSizing.homeDisplayRatio(1 / (loaded.first ?? 1))
      for index in items.indices {
        if var value = items[index].mediaWriting {
          value.sourceAspectRatio = loaded[index]
          if automaticallySizedCoverIndices.contains(index) { value.homeAspectRatio = 1 / resolvedHomeRatio }
          items[index].mediaWriting = value
        }
      }
    }
    .onChange(of: ratios.count) { _, count in
      if coverMode && count == items.count && !didFocusCoverHeadline {
        didFocusCoverHeadline = true
        textFocused = true
      }
    }
    .task(id: selected) { await loadMedia() }
    .onAppear { MIRAPlaybackCoordinator.pauseAll(reason: "media_writing_editor_open") }
    .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
    .onDisappear { cleanup() }
  }

  private func canvas(size: CGSize) -> some View {
    ZStack(alignment: .topLeading) {
      let source = resolvedWriting.sourceRect(in: size, fill: true)
      Group {
        if let player { WritingVideoCanvas(player: player) }
        else if let image { Image(uiImage: image).resizable().scaledToFill() }
        else if let loadError { Text(loadError).foregroundStyle(.secondary) }
        else { ProgressView() }
      }.frame(width: source.width, height: source.height).clipped()
        .offset(x: source.minX, y: source.minY)
        .accessibilityIdentifier("mediaWriting.canvas")
        .contentShape(Rectangle())
        .onTapGesture { panel = "text"; textFocused = true }
        .gesture(DragGesture().onChanged { gesture in
          guard adjustsCrop else { return }
          textFocused = false
          if cropOrigin == nil { cropOrigin = CGPoint(x: writing.cropX ?? 0.5, y: writing.cropY ?? 0.5) }
          var value = writing
          if source.width > size.width + 1 { value.cropX = min(1, max(0, cropOrigin!.x - gesture.translation.width / (source.width - size.width))) }
          if source.height > size.height + 1 { value.cropY = min(1, max(0, cropOrigin!.y - gesture.translation.height / (source.height - size.height))) }
          writing = value
        }.onEnded { _ in cropOrigin = nil })
      // Advisory preview, not a permanent overlay on published media.
      if !coverMode && items.first?.mediaWriting?.showsStamp != false { Rectangle().fill(.black.opacity(0.08))
        .overlay(alignment: .topLeading) {
          Text("Stamp area").font(.caption2).padding(6).background(.ultraThinMaterial)
        }
        .frame(width: size.width * 0.73, height: size.height * 0.50)
        .offset(x: size.width * 0.054, y: size.height * 0.48)
        .allowsHitTesting(false).accessibilityHidden(true) }
      if coverMode {
        coverHeadlineField(in: size)
      } else if !writing.text.isEmpty {
        CaptroMediaWritingLayer(writing: resolvedWriting, container: size)
        let rect = resolvedWriting.textRect(in: size, fill: true)
        Color.clear.frame(width: max(44, rect.width), height: max(44, rect.height))
          .contentShape(Rectangle()).position(x: rect.midX, y: rect.midY)
          .onTapGesture { panel = "text"; textFocused = true }
          .allowsHitTesting(!adjustsCrop)
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
      if !coverMode && writing.text.isEmpty {
        Button("Add text") { panel = "text"; textFocused = true }
          .font(.subheadline.weight(.medium)).padding(10)
          .background(.regularMaterial, in: Capsule())
          .position(x: size.width / 2, y: size.height / 2)
      }
      if !coverMode && guide {
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
  }
  private func coverHeadlineField(in size: CGSize) -> some View {
    let value = resolvedWriting
    let source = value.sourceRect(in: size, fill: true)
    let rect = value.textRect(in: size, fill: true)
    return TextField("Write a headline", text: coverTextBinding, axis: .vertical)
      .font(Font(value.font(mediaWidth: source.width, visibleWidth: size.width)))
      .lineSpacing(-2)
      .foregroundStyle(value.tint)
      .multilineTextAlignment(value.alignment == "center" ? .center : value.alignment == "right" ? .trailing : .leading)
      .lineLimit(1...4)
      .textFieldStyle(.plain)
      .textInputAutocapitalization(.characters)
      .padding(value.readability ? 7 : 0)
      .frame(width: rect.width + (value.readability ? 14 : 0))
      .background(value.readability ? (value.color == "black" || value.color == "green" ? Color.white : Color.black) : .clear)
      .overlay { if value.readability { Rectangle().strokeBorder(value.color == "black" || value.color == "green" ? Color.black : Color.white, lineWidth: 1) } }
      .position(x: rect.midX, y: rect.midY)
      .focused($textFocused)
      .accessibilityLabel("Cover headline")
      .accessibilityIdentifier("mediaWriting.text")
  }
  private var resolvedWriting: CaptroMediaWriting {
    var value = writing; value.sourceAspectRatio = sourceRatio; return value
  }
  @ViewBuilder private var controls: some View {
    switch panel {
    case "style":
      Picker("Style", selection: writingBinding.style) {
        Text("Handwritten").tag("handwritten"); Text("Bold").tag("bold"); Text("Classic").tag("classic")
      }.pickerStyle(.segmented)
      Picker("Size", selection: writingBinding.size) {
        Text("Small").tag("small"); Text("Medium").tag("medium"); Text("Large").tag("large")
      }.pickerStyle(.segmented)
      Picker("Text color", selection: writingBinding.color) {
        Text("White").tag("white"); Text("Black").tag("black")
        Text("Green").tag("green"); Text("Cream").tag("cream")
      }.pickerStyle(.menu)
      Toggle("Rectangular backing", isOn: writingBinding.readability).font(.subheadline)
    case "alignment":
      Picker("Text alignment", selection: writingBinding.alignment) {
        Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right")
      }.pickerStyle(.segmented)
    case "position":
      if selected == 0 && !coverMode {
        Toggle("Show Captro stamp", isOn: Binding(get: { writing.showsStamp != false }, set: { writing.showsStamp = $0 }))
          .font(.subheadline)
      }
      Text(adjustsCrop ? "Drag the photo to adjust Home’s crop. The original stays intact." : "Drag the writing on the photo, or choose a position.")
        .font(.footnote).foregroundStyle(.secondary)
      HStack {
        Button("Upper") { positionInCanvas(y: 0.22) }
        Button("Center") { positionInCanvas(y: 0.5) }
        Button("Lower") { positionInCanvas(y: 0.75) }
      }.buttonStyle(.bordered)
    default:
      TextField("Your short phrase", text: writingBinding.text, axis: .vertical)
        .lineLimit(1...4).focused($textFocused).font(.body)
        .accessibilityIdentifier("mediaWriting.text")
      Text("\(writing.text.count)/\(writing.characterLimit) · Up to 4 lines").font(.caption).foregroundStyle(.secondary)
    }
  }
  private func positionInCanvas(y: CGFloat) {
    let size = CGSize(width: 1000, height: 1000 * homeRatio)
    let source = resolvedWriting.sourceRect(in: size, fill: true)
    place(x: (size.width / 2 - source.minX) / source.width,
      y: (size.height * y - source.minY) / source.height, canvas: size)
  }
  private func place(x: CGFloat, y: CGFloat, canvas: CGSize) {
    var value = resolvedWriting
    let source = value.sourceRect(in: canvas, fill: true)
    let text = value.measuredSize(mediaWidth: source.width, visibleWidth: canvas.width)
    let minX = (12 - source.minX + text.width / 2) / source.width
    let maxX = (canvas.width - 12 - source.minX - text.width / 2) / source.width
    let minY = (52 - source.minY + text.height / 2) / source.height
    let maxY = (canvas.height - 52 - source.minY - text.height / 2) / source.height
    value.x = min(maxX, max(minX, x)); value.y = min(maxY, max(minY, y))
    writing = value
  }
  private func select(_ index: Int) {
    guard items.indices.contains(index) else { return }
    if !coverMode { textFocused = false }
    selected = index
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
