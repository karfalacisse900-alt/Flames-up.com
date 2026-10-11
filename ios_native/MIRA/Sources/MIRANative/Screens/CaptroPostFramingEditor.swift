import SwiftUI

/// Transactional, nondestructive framing. One album format, independent focal
/// positions per asset. Cancel never replaces the draft or original files.
struct CaptroPostFramingEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var items: [MIRAPickedMedia]
  @State private var selected: Int
  @State private var origin: CaptroPostMediaGeometry?
  @State private var ready = false
  @State private var failure: String?
  let onSave: ([MIRAPickedMedia]) -> Void
  init(items: [MIRAPickedMedia], selected: Int = 0, onSave: @escaping ([MIRAPickedMedia]) -> Void) {
    _items = State(initialValue: items); _selected = State(initialValue: min(selected, max(0, items.count - 1)))
    self.onSave = onSave
  }
  private var geometry: CaptroPostMediaGeometry {
    items.indices.contains(selected) ? items[selected].postFraming ?? .init(sourceAspectRatio: 0.8) : .init(sourceAspectRatio: 0.8)
  }
  private var clippedWritingIndex: Int? {
    items.indices.first { index in
      guard let framing = items[index].postFraming, let text = items[index].mediaWriting,
        !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
      let size = framing.size(width: 390)
      let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
      return !bounds.contains(framing.applying(to: text).textRect(in: size, fill: true))
    }
  }
  var body: some View {
    NavigationStack {
      GeometryReader { page in
        ScrollView {
          VStack(spacing: 16) {
            if ready, items.indices.contains(selected) {
              let width = min(page.size.width - 32, max(160, page.size.height - 190) * geometry.displayAspectRatio)
              let size = geometry.size(width: width)
              CaptroPickedMediaPreview(media: items[selected], size: size)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                  let start = origin ?? geometry
                  if origin == nil { origin = start }
                  let rect = start.sourceRect(in: size)
                  var updated = start
                  if rect.width > size.width + 0.5 { updated.cropX = min(1, max(0, start.cropX - value.translation.width / (rect.width - size.width))) }
                  if rect.height > size.height + 0.5 { updated.cropY = min(1, max(0, start.cropY - value.translation.height / (rect.height - size.height))) }
                  items[selected].postFraming = updated
                }.onEnded { _ in origin = nil })
                .accessibilityLabel("Crop preview")
                .accessibilityHint("Use the vertical or horizontal position adjustment below to reposition the media")
                .accessibilityIdentifier("post.crop.preview")
              Picker("Post format", selection: Binding(get: { geometry.displayAspectRatio }, set: { ratio in
                for index in items.indices { items[index].postFraming?.displayAspectRatio = ratio }
              })) {
                Text("4:5").tag(0.8); Text("1:1").tag(1.0); Text("3:4").tag(0.75); Text("16:9").tag(16.0 / 9)
              }.pickerStyle(.segmented).accessibilityIdentifier("post.crop.format")
              Text(items.count > 1 ? "One format for this carousel. Drag each photo to frame it." : "Drag to frame. Your original stays unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
              if let index = clippedWritingIndex {
                Text("Writing on item \(index + 1) is outside this crop. Reposition the photo or choose another format.")
                  .font(.footnote).foregroundStyle(.red)
              }
              // Adjustable semantic controls remain available to VoiceOver,
              // without adding another visible design toolbar.
              Color.clear.frame(height: 1).accessibilityElement()
                .accessibilityLabel("Vertical crop position")
                .accessibilityValue("\(Int(geometry.cropY * 100)) percent")
                .accessibilityAdjustableAction { direction in adjust(vertical: true, direction: direction) }
              Color.clear.frame(height: 1).accessibilityElement()
                .accessibilityLabel("Horizontal crop position")
                .accessibilityValue("\(Int(geometry.cropX * 100)) percent")
                .accessibilityAdjustableAction { direction in adjust(vertical: false, direction: direction) }
              if items.count > 1 {
                HStack {
                  Button { selected -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(selected == 0).accessibilityLabel("Previous media")
                  Text("\(selected + 1) / \(items.count)").monospacedDigit()
                  Button { selected += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(selected == items.count - 1).accessibilityLabel("Next media")
                }
              }
            } else if let failure { Text(failure).foregroundStyle(.secondary) }
            else { ProgressView("Preparing media") }
          }.padding(16).frame(maxWidth: .infinity)
        }
      }
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("Frame media").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { onSave(items); dismiss() }.disabled(!ready || clippedWritingIndex != nil)
            .accessibilityIdentifier("post.crop.done")
        }
      }
    }
    .task {
      var prepared: [MIRAPickedMedia] = []
      for item in items { prepared.append(await item.preparedForPost()) }
      guard !Task.isCancelled else { return }
      guard !prepared.isEmpty, prepared.allSatisfy({ $0.sourceDimension?.originalAspectRatio != nil }) else {
        failure = "Couldn’t read this media’s dimensions. Cancel and select it again."
        return
      }
      let ratio = prepared.first?.postFraming?.displayAspectRatio ?? 0.8
      for index in prepared.indices { prepared[index].postFraming?.displayAspectRatio = ratio }
      items = prepared; ready = true
    }
  }
  private func adjust(vertical: Bool, direction: AccessibilityAdjustmentDirection) {
    var next = geometry
    let delta = direction == .increment ? 0.05 : -0.05
    if vertical { next.cropY = min(1, max(0, next.cropY + delta)) }
    else { next.cropX = min(1, max(0, next.cropX + delta)) }
    items[selected].postFraming = next
  }
}

struct CaptroPickedMediaPreview: View {
  let media: MIRAPickedMedia
  let size: CGSize
  @State private var file: URL?
  @State private var error = false
  @State private var previewID = UUID()
  var body: some View {
    Group {
      if let file {
        CaptroPostMediaView(url: file.absoluteString, geometry: media.postFraming ?? .init(sourceAspectRatio: 0.8),
          size: size, isVideo: media.kind == .video, shouldPlay: false, writing: media.mediaWriting)
      } else if error { Text("Couldn’t open media. Return and select it again.").font(.footnote) }
      else { ProgressView() }
    }
    .frame(width: size.width, height: size.height)
    .task(id: media.localID) {
      error = false
      if let file { try? FileManager.default.removeItem(at: file); self.file = nil }
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-framing-\(previewID)-\(media.localID).\(URL(fileURLWithPath: media.fileName).pathExtension)")
      do {
        try await Task.detached(priority: .utility) { try media.data.write(to: url, options: .atomic) }.value
        guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
        file = url
      } catch { self.error = true }
    }
    .onDisappear { if let file { try? FileManager.default.removeItem(at: file); self.file = nil } }
  }
}
