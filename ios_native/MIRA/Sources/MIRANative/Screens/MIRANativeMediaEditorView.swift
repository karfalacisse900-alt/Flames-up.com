import AVKit
import PhotosUI
import SwiftUI
import UIKit

public enum MIRANativeMediaEditorMode {
  case post
  case story
}

public struct MIRANativeMediaEditorView: View {
  private let media: MIRAPickedMedia
  private let mode: MIRANativeMediaEditorMode
  private let onClose: (() -> Void)?
  private let onComplete: (MIRAPickedMedia) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var recipe: MIRANativeEditRecipe
  @State private var previewImage: UIImage?
  @State private var videoThumbnail: UIImage?
  @State private var player: AVPlayer?
  @State private var previewVideoURL: URL?
  @State private var activePanel: EditorPanel = .filters
  @State private var selectedTextID: String?
  @State private var editingText = false
  @State private var draftText = ""
  @State private var isExporting = false
  @State private var errorMessage: String?

  public init(
    media: MIRAPickedMedia,
    mode: MIRANativeMediaEditorMode,
    onClose: (() -> Void)? = nil,
    onComplete: @escaping (MIRAPickedMedia) -> Void
  ) {
    self.media = media
    self.mode = mode
    self.onClose = onClose
    self.onComplete = onComplete
    let mediaType: MIRANativeEditorMediaType = media.kind == .video ? .video : .photo
    _recipe = State(initialValue: MIRANativeEditRecipe(
      mediaType: mediaType,
      aspectRatio: mode == .story ? .story9x16 : .original
    ))
  }

  public var body: some View {
    GeometryReader { proxy in
      let previewWidth = proxy.size.width
      let previewHeight = previewHeight(for: proxy.size)

      VStack(spacing: 0) {
        editorTopBar
          .padding(.horizontal, 18)
          .padding(.top, max(proxy.safeAreaInsets.top, 10))
          .padding(.bottom, 12)

        ZStack {
          editorPreview(width: previewWidth, height: previewHeight)
            .frame(width: previewWidth, height: previewHeight)
            .clipped()

          ForEach($recipe.textLayers) { $layer in
            MIRAEditableTextLayerView(
              layer: $layer,
              containerSize: CGSize(width: previewWidth, height: previewHeight),
              isSelected: selectedTextID == layer.id
            )
            .onTapGesture {
              selectedTextID = layer.id
            }
          }
        }
        .background(Color.black)
        .frame(width: previewWidth, height: previewHeight)
        .contentShape(Rectangle())
        .onTapGesture {
          selectedTextID = nil
        }

        if let selectedTextIndex {
          selectedTextControls(index: selectedTextIndex)
            .padding(.top, 10)
            .padding(.horizontal, 16)
        }

        editorPanel
          .padding(.top, 12)
          .padding(.bottom, max(proxy.safeAreaInsets.bottom, 14))
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .background((mode == .story ? Color.black : MIRATheme.Color.surface).ignoresSafeArea())
      .overlay {
        if isExporting {
          exportingOverlay
        }
      }
      .alert("Edit text", isPresented: $editingText) {
        TextField("Text", text: $draftText)
        Button("Cancel", role: .cancel) {}
        Button("Done") {
          if let selectedTextIndex {
            recipe.textLayers[selectedTextIndex].text = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add text" : draftText
          }
        }
      }
      .task(id: filterPreviewKey) {
        await refreshPreview()
      }
      .task {
        await prepareVideoIfNeeded()
      }
      .onDisappear {
        player?.pause()
        if let previewVideoURL {
          try? FileManager.default.removeItem(at: previewVideoURL)
        }
      }
    }
  }

  private var editorTopBar: some View {
    HStack {
      Button {
        player?.pause()
        closeEditor()
      } label: {
        Image(systemName: mode == .story ? "xmark" : "chevron.left")
          .font(.system(size: mode == .story ? 26 : 30, weight: .medium))
          .foregroundStyle(mode == .story ? .white : MIRATheme.Color.textPrimary)
          .frame(width: 50, height: 50)
      }
      .buttonStyle(.plain)

      Spacer()

      Button {
        Task { await exportMedia() }
      } label: {
        Image(systemName: isExporting ? "hourglass" : "square.and.arrow.down")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(mode == .story ? MIRATheme.Color.textPrimary : .white)
          .frame(width: 50, height: 50)
          .background(mode == .story ? Color.white : MIRATheme.Color.forest)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(isExporting)
      .accessibilityLabel(isExporting ? "Saving edit" : "Save edit")
    }
  }

  @ViewBuilder
  private func editorPreview(width: CGFloat, height: CGFloat) -> some View {
    if media.kind == .image {
      if let previewImage {
        Image(uiImage: previewImage)
          .resizable()
          .scaledToFill()
      } else {
        Color.black
          .overlay { ProgressView().tint(.white) }
      }
    } else {
      ZStack {
        if let player {
          VideoPlayer(player: player)
            .onAppear { player.play() }
        } else if let videoThumbnail {
          Image(uiImage: videoThumbnail)
            .resizable()
            .scaledToFill()
        } else {
          Color.black
            .overlay { ProgressView().tint(.white) }
        }

        Button {
          togglePlayback()
        } label: {
          Image(systemName: "playpause.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(.black.opacity(0.28))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(18)
      }
    }
  }

  private var editorPanel: some View {
    VStack(spacing: 14) {
      HStack(spacing: 12) {
        panelButton(.text, systemImage: "textformat", title: "Text")
        panelButton(.filters, systemImage: "camera.filters", title: "Filters")
        panelButton(.adjustments, systemImage: "slider.horizontal.3", title: "Adjust")
      }
      .padding(.horizontal, 16)

      switch activePanel {
      case .text:
        textToolPanel
      case .filters:
        filterCarousel
      case .adjustments:
        adjustmentSliders
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.red.opacity(0.9))
          .padding(.horizontal, 18)
      }
    }
    .foregroundStyle(mode == .story ? .white : MIRATheme.Color.textPrimary)
  }

  private func panelButton(_ panel: EditorPanel, systemImage: String, title: String) -> some View {
    Button {
      withAnimation(.snappy(duration: 0.18)) {
        activePanel = panel
      }
    } label: {
      Label(title, systemImage: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(activePanel == panel ? activePanelColor : inactivePanelColor)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var textToolPanel: some View {
    HStack(spacing: 12) {
      Button {
        let next = MIRANativeTextLayer(zIndex: recipe.textLayers.count)
        recipe.textLayers.append(next)
        selectedTextID = next.id
      } label: {
        Label("Add text", systemImage: "plus")
          .font(.system(size: 16, weight: .semibold))
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(activePanelColor)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)

      Button {
        if let selectedTextIndex {
          draftText = recipe.textLayers[selectedTextIndex].text
          editingText = true
        }
      } label: {
        Text("Edit")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 88, height: 48)
          .background(inactivePanelColor)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(selectedTextIndex == nil)
      .opacity(selectedTextIndex == nil ? 0.48 : 1)
    }
    .padding(.horizontal, 16)
  }

  private var filterCarousel: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(MIRANativeEditorFilter.allCases) { filter in
          Button {
            recipe.selectedFilter = filter
          } label: {
            Text(filter.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(recipe.selectedFilter == filter ? .white : panelTextColor)
              .padding(.horizontal, 16)
              .frame(height: 42)
              .background(recipe.selectedFilter == filter ? MIRATheme.Color.forest : inactivePanelColor)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
    }
  }

  private var adjustmentSliders: some View {
    VStack(spacing: 8) {
      editorSlider(title: "Brightness", value: $recipe.brightness, range: -0.25...0.25)
      editorSlider(title: "Contrast", value: $recipe.contrast, range: 0.75...1.35)
      editorSlider(title: "Saturation", value: $recipe.saturation, range: 0.65...1.45)
    }
    .padding(.horizontal, 16)
  }

  private func editorSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 78, alignment: .leading)
      Slider(value: value, in: range)
        .tint(mode == .story ? .white : MIRATheme.Color.forest)
    }
  }

  private func selectedTextControls(index: Int) -> some View {
    HStack(spacing: 10) {
      ForEach(["#FFFFFF", "#111511", "#F7F1E8", "#D8FF40", "#E04F6C"], id: \.self) { color in
        Button {
          recipe.textLayers[index].colorHex = color
        } label: {
          Circle()
            .fill(Color(uiColor: UIColor(hex: color)))
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: recipe.textLayers[index].colorHex == color ? 3 : 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
      }

      Spacer()

      Button {
        recipe.textLayers[index].alignment = nextAlignment(after: recipe.textLayers[index].alignment)
      } label: {
        Image(systemName: "text.aligncenter")
          .frame(width: 42, height: 36)
          .background(inactivePanelColor)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)

      Button(role: .destructive) {
        let removedID = recipe.textLayers[index].id
        recipe.textLayers.remove(at: index)
        if selectedTextID == removedID { selectedTextID = nil }
      } label: {
        Image(systemName: "trash")
          .frame(width: 42, height: 36)
          .background(inactivePanelColor)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
  }

  private var exportingOverlay: some View {
    ZStack {
      Color.black.opacity(0.26).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView()
          .tint(.white)
        Text("Exporting")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
      }
      .padding(24)
      .background(.black.opacity(0.58))
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
  }

  private var activePanelColor: Color {
    mode == .story ? .white.opacity(0.22) : MIRATheme.Color.forestSoft
  }

  private var inactivePanelColor: Color {
    mode == .story ? .white.opacity(0.12) : MIRATheme.Color.surfaceSoft
  }

  private var panelTextColor: Color {
    mode == .story ? .white : MIRATheme.Color.textPrimary
  }

  private var selectedTextIndex: Int? {
    guard let selectedTextID else { return nil }
    return recipe.textLayers.firstIndex(where: { $0.id == selectedTextID })
  }

  private var filterPreviewKey: String {
    "\(recipe.selectedFilter.rawValue)-\(recipe.brightness)-\(recipe.contrast)-\(recipe.saturation)-\(media.data.count)"
  }

  private func previewHeight(for size: CGSize) -> CGFloat {
    switch mode {
    case .story:
      return min(size.height * 0.72, size.width * 16 / 9)
    case .post:
      return min(size.height * 0.56, size.width * 1.25)
    }
  }

  private func refreshPreview() async {
    guard media.kind == .image else { return }
    previewImage = await MIRANativeMediaEditorRenderer.previewImage(from: media.data, recipe: recipe)
  }

  private func prepareVideoIfNeeded() async {
    guard media.kind == .video else { return }
    videoThumbnail = await MIRANativeMediaEditorRenderer.videoThumbnail(from: media.data, fileName: media.fileName)
    let ext = URL(fileURLWithPath: media.fileName).pathExtension.isEmpty ? "mov" : URL(fileURLWithPath: media.fileName).pathExtension
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    do {
      try media.data.write(to: url, options: .atomic)
      if let previewVideoURL {
        try? FileManager.default.removeItem(at: previewVideoURL)
      }
      previewVideoURL = url
      player = AVPlayer(url: url)
      player?.isMuted = false
    } catch {
      errorMessage = "Video preview could not load."
    }
  }

  private func togglePlayback() {
    guard let player else { return }
    if player.timeControlStatus == .playing {
      player.pause()
    } else {
      player.play()
    }
  }

  private func exportMedia() async {
    guard !isExporting else { return }
    errorMessage = nil
    isExporting = true
    defer { isExporting = false }

    do {
      let edited: MIRAPickedMedia
      if media.kind == .video {
        edited = try await MIRANativeMediaEditorExporter.exportVideo(media: media, recipe: recipe)
      } else {
        edited = try await MIRANativeMediaEditorExporter.exportPhoto(media: media, recipe: recipe)
      }
      onComplete(edited)
      closeEditor()
    } catch is CancellationError {
      errorMessage = "Export was cancelled."
    } catch {
      errorMessage = "Could not export this edit. Please try again."
    }
  }

  private func closeEditor() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  private func nextAlignment(after alignment: String) -> String {
    switch alignment {
    case "center": return "left"
    case "left": return "right"
    default: return "center"
    }
  }

  private enum EditorPanel {
    case text
    case filters
    case adjustments
  }
}

private struct MIRAEditableTextLayerView: View {
  @Binding var layer: MIRANativeTextLayer
  let containerSize: CGSize
  let isSelected: Bool

  @State private var dragStart: CGPoint?
  @State private var scaleStart: CGFloat?
  @State private var rotationStart: CGFloat?

  var body: some View {
    Text(layer.text)
      .font(.system(size: layer.fontSize * layer.scale, weight: .semibold))
      .foregroundStyle(Color(uiColor: UIColor(hex: layer.colorHex)))
      .multilineTextAlignment(layer.swiftUITextAlignment)
      .shadow(color: .black.opacity(0.32), radius: 8, y: 2)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(.white.opacity(0.82), lineWidth: 1.5)
        }
      }
      .position(x: layer.x * containerSize.width, y: layer.y * containerSize.height)
      .rotationEffect(.radians(layer.rotation))
      .gesture(dragGesture)
      .simultaneousGesture(scaleGesture)
      .simultaneousGesture(rotationGesture)
      .accessibilityLabel("Editable text layer")
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        if dragStart == nil {
          dragStart = CGPoint(x: layer.x, y: layer.y)
        }
        guard let dragStart else { return }
        layer.x = min(max(dragStart.x + value.translation.width / max(1, containerSize.width), 0.05), 0.95)
        layer.y = min(max(dragStart.y + value.translation.height / max(1, containerSize.height), 0.05), 0.95)
      }
      .onEnded { _ in
        dragStart = nil
      }
  }

  private var scaleGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if scaleStart == nil {
          scaleStart = layer.scale
        }
        layer.scale = min(max((scaleStart ?? 1) * value, 0.45), 3.0)
      }
      .onEnded { _ in
        scaleStart = nil
      }
  }

  private var rotationGesture: some Gesture {
    RotationGesture()
      .onChanged { value in
        if rotationStart == nil {
          rotationStart = layer.rotation
        }
        layer.rotation = (rotationStart ?? 0) + value.radians
      }
      .onEnded { _ in
        rotationStart = nil
      }
  }
}

private extension MIRANativeTextLayer {
  var swiftUITextAlignment: TextAlignment {
    switch alignment {
    case "left": return .leading
    case "right": return .trailing
    default: return .center
    }
  }
}
