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
  @State private var activePanel: EditorPanel
  @State private var videoDurationSeconds: Double = 0
  @State private var selectedTextID: String?
  @State private var selectedStickerID: String?
  @State private var showsVerticalGuide = false
  @State private var showsHorizontalGuide = false
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
      aspectRatio: mode == .story ? .story9x16 : .portrait3x4
    ))
    _activePanel = State(initialValue: mode == .post ? .adjustments : .crop)
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

          if media.kind == .image {
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture {
                selectedTextID = nil
                selectedStickerID = nil
              }
          }

          ForEach($recipe.textLayers) { $layer in
            MIRAEditableTextLayerView(
              layer: $layer,
              containerSize: CGSize(width: previewWidth, height: previewHeight),
              isSelected: selectedTextID == layer.id,
              onSnapChange: updateSnapGuides
            )
            .zIndex(Double(layer.zIndex))
            .onTapGesture {
              selectedStickerID = nil
              selectedTextID = layer.id
            }
            .onTapGesture(count: 2) {
              selectedStickerID = nil
              selectedTextID = layer.id
              draftText = layer.text
              editingText = true
            }
          }

          ForEach(recipe.stickerLayers ?? []) { layer in
            MIRAEditableStickerLayerView(
              layer: stickerBinding(for: layer.id),
              containerSize: CGSize(width: previewWidth, height: previewHeight),
              isSelected: selectedStickerID == layer.id,
              onSnapChange: updateSnapGuides
            )
            .zIndex(Double(layer.zIndex))
            .onTapGesture {
              selectedTextID = nil
              selectedStickerID = layer.id
            }
          }

          if showsVerticalGuide {
            Rectangle()
              .fill(Color.white.opacity(0.76))
              .frame(width: 1, height: previewHeight)
              .allowsHitTesting(false)
          }
          if showsHorizontalGuide {
            Rectangle()
              .fill(Color.white.opacity(0.76))
              .frame(width: previewWidth, height: 1)
              .allowsHitTesting(false)
          }
        }
        .background(Color.black)
        .frame(width: previewWidth, height: previewHeight)
        .clipped()
        if let selectedTextIndex {
          selectedTextControls(index: selectedTextIndex)
            .padding(.top, 10)
            .padding(.horizontal, 16)
        } else if let selectedStickerIndex {
          selectedStickerControls(index: selectedStickerIndex)
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
      .sheet(isPresented: $editingText) {
        MIRAEditorTextEntrySheet(text: $draftText) {
          applyDraftText()
        }
        .presentationDetents([.height(270)])
        .presentationDragIndicator(.visible)
        .presentationBackground(MIRATheme.Color.surface)
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
    .statusBarHidden(mode == .story)
    .miraStatusBarHidden(mode == .story)
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
        HStack(spacing: 7) {
          if isExporting {
            ProgressView()
              .tint(mode == .story ? MIRATheme.Color.textPrimary : .white)
              .scaleEffect(0.72)
          }
          Text(isExporting ? "Saving" : "Done")
            .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(mode == .story ? MIRATheme.Color.textPrimary : .white)
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(mode == .story ? Color.white : MIRATheme.Color.forest)
        .clipShape(Capsule())
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
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 9) {
          ForEach(availableEditorPanels, id: \.self) { panel in
            panelButton(panel, systemImage: panel.systemImage, title: panel.title)
              .frame(width: 106)
          }
        }
        .padding(.horizontal, 16)
      }
      switch activePanel {
      case .crop:
        cropToolPanel
      case .text:
        textToolPanel
      case .decorate:
        decorateToolPanel
      case .filters:
        filterCarousel
      case .adjustments:
        adjustmentSliders
      case .trim:
        trimToolPanel
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

  private var availableEditorPanels: [EditorPanel] {
    var panels: [EditorPanel] = mode == .post ? [.adjustments, .filters] : [.crop, .adjustments, .filters]
    if media.kind == .video {
      panels.append(.trim)
    } else {
      panels.append(contentsOf: [.text, .decorate])
    }
    return panels
  }
  private var cropToolPanel: some View {
    VStack(spacing: 12) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(availableRatios, id: \.self) { ratio in
            Button {
              recipe.aspectRatio = ratio
            } label: {
              Text(ratio.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(recipe.aspectRatio == ratio ? .white : panelTextColor)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(recipe.aspectRatio == ratio ? MIRATheme.Color.forest : inactivePanelColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16)
      }

      Button {
        recipe.rotationQuarterTurns = (recipe.rotationQuarterTurns + 1) % 4
      } label: {
        Label("Rotate", systemImage: "rotate.right")
          .font(.system(size: 16, weight: .semibold))
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(inactivePanelColor)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 16)
      .disabled(media.kind == .video)
      .opacity(media.kind == .video ? 0.45 : 1)
    }
  }

  private var textToolPanel: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Button {
          let next = MIRANativeTextLayer(fontSize: 36, zIndex: nextLayerIndex)
          recipe.textLayers.append(next)
          selectedStickerID = nil
          selectedTextID = next.id
          draftText = next.text
          editingText = true
        } label: {
          Label("Add text", systemImage: "plus")
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(activePanelColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)

        Button {
          guard let selectedTextIndex else { return }
          draftText = recipe.textLayers[selectedTextIndex].text
          editingText = true
        } label: {
          Label("Edit", systemImage: "pencil")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 92, height: 44)
            .background(inactivePanelColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedTextIndex == nil)
        .opacity(selectedTextIndex == nil ? 0.48 : 1)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(MIRANativeTextStyle.allCases) { style in
            Button {
              guard let selectedTextIndex else { return }
              recipe.textLayers[selectedTextIndex].style = style
              if style == .label, recipe.textLayers[selectedTextIndex].backgroundStyle == MIRANativeTextBackgroundStyle.none {
                recipe.textLayers[selectedTextIndex].backgroundStyle = .label
              }
            } label: {
              Text(style.title)
                .font(editorFont(for: style, size: 13))
                .foregroundStyle(selectedTextStyle == style ? selectedChipTextColor : panelTextColor)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(selectedTextStyle == style ? selectedChipColor : inactivePanelColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedTextIndex == nil)
          }
        }
      }

      if let selectedTextIndex {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(MIRANativeTextBackgroundStyle.allCases) { style in
              Button {
                recipe.textLayers[selectedTextIndex].backgroundStyle = style
              } label: {
                Text(style.title)
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(selectedTextBackground == style ? selectedChipTextColor : panelTextColor)
                  .padding(.horizontal, 12)
                  .frame(height: 34)
                  .background(selectedTextBackground == style ? selectedChipColor : inactivePanelColor)
                  .clipShape(Capsule())
              }
              .buttonStyle(.plain)
            }
          }
        }

        VStack(spacing: 6) {
          compactLayerSlider(
            title: "Size",
            value: Binding(
              get: { Double(recipe.textLayers[selectedTextIndex].fontSize) },
              set: { recipe.textLayers[selectedTextIndex].fontSize = CGFloat($0) }
            ),
            range: 16...74
          )
          compactLayerSlider(
            title: "Width",
            value: Binding(
              get: { Double(recipe.textLayers[selectedTextIndex].width ?? 0.76) },
              set: { recipe.textLayers[selectedTextIndex].width = CGFloat($0) }
            ),
            range: 0.28...0.92
          )
          compactLayerSlider(
            title: "Opacity",
            value: Binding(
              get: { Double(recipe.textLayers[selectedTextIndex].opacity ?? 1) },
              set: { recipe.textLayers[selectedTextIndex].opacity = CGFloat($0) }
            ),
            range: 0.15...1
          )
        }
      }
    }
    .padding(.horizontal, 16)
  }

  private var decorateToolPanel: some View {
    VStack(spacing: 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(MIRANativeStickerAsset.allCases) { asset in
            Button {
              let next = MIRANativeStickerLayer(assetType: asset, zIndex: nextLayerIndex)
              var layers = recipe.stickerLayers ?? []
              layers.append(next)
              recipe.stickerLayers = layers
              selectedTextID = nil
              selectedStickerID = next.id
            } label: {
              VStack(spacing: 5) {
                Image(systemName: asset.systemImage)
                  .font(.system(size: 20, weight: .medium))
                Text(asset.title)
                  .font(.system(size: 10, weight: .semibold))
              }
              .foregroundStyle(panelTextColor)
              .frame(width: 66, height: 56)
              .background(inactivePanelColor)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16)
      }

      if let selectedStickerIndex {
        compactLayerSlider(
          title: "Opacity",
          value: Binding(
            get: { Double((recipe.stickerLayers ?? [])[selectedStickerIndex].opacity) },
            set: { value in updateSticker(at: selectedStickerIndex) { $0.opacity = CGFloat(value) } }
          ),
          range: 0.15...1
        )
        .padding(.horizontal, 16)
      }
    }
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
      editorSlider(title: "Exposure", value: $recipe.exposure, range: -1...1)
      editorSlider(title: "Warmth", value: $recipe.warmth, range: -1...1)
      editorSlider(title: "Saturation", value: $recipe.saturation, range: 0.65...1.45)
      editorSlider(title: "Sharpness", value: $recipe.sharpness, range: 0...1.2)
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

  private func compactLayerSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    HStack(spacing: 10) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 50, alignment: .leading)
      Slider(value: value, in: range)
        .tint(mode == .story ? .white : MIRATheme.Color.forest)
        .frame(height: 20)
    }
  }

  private var trimToolPanel: some View {
    VStack(spacing: 12) {
      if videoDurationSeconds > 0 {
        HStack {
          Text("Start \(formatTime(recipe.trimStartSeconds))")
            .font(.system(size: 13, weight: .semibold))
          Spacer()
          Text("End \(formatTime(effectiveTrimEnd))")
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(panelTextColor.opacity(0.78))

        Slider(
          value: Binding(
            get: { recipe.trimStartSeconds },
            set: { recipe.trimStartSeconds = min(max(0, $0), max(0, effectiveTrimEnd - 0.4)) }
          ),
          in: 0...max(0.1, videoDurationSeconds)
        )
        .tint(mode == .story ? .white : MIRATheme.Color.forest)

        Slider(
          value: Binding(
            get: { effectiveTrimEnd },
            set: { recipe.trimEndSeconds = min(max(recipe.trimStartSeconds + 0.4, $0), videoDurationSeconds) }
          ),
          in: 0...max(0.1, videoDurationSeconds)
        )
        .tint(mode == .story ? .white : MIRATheme.Color.forest)
      } else {
        HStack(spacing: 10) {
          ProgressView()
            .tint(mode == .story ? .white : MIRATheme.Color.forest)
          Text("Preparing video trim")
            .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(inactivePanelColor)
        .clipShape(Capsule())
      }
    }
    .padding(.horizontal, 16)
  }

  private func selectedTextControls(index: Int) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        layerControlButton("Edit", systemImage: "pencil") {
          draftText = recipe.textLayers[index].text
          editingText = true
        }
        layerControlButton("Duplicate", systemImage: "plus.square.on.square") {
          duplicateTextLayer(at: index)
        }
        layerControlButton("Back", systemImage: "square.2.layers.3d.bottom.filled") {
          recipe.textLayers[index].zIndex -= 1
        }
        layerControlButton("Forward", systemImage: "square.2.layers.3d.top.filled") {
          recipe.textLayers[index].zIndex += 1
        }
        layerControlButton("Align", systemImage: "text.aligncenter") {
          recipe.textLayers[index].alignment = nextAlignment(after: recipe.textLayers[index].alignment)
        }

        ForEach(["#FFFFFF", "#111511", "#F7F1E8", "#D8FF40", "#E04F6C"], id: \.self) { color in
          Button {
            recipe.textLayers[index].colorHex = color
          } label: {
            Circle()
              .fill(Color(uiColor: UIColor(hex: color)))
              .frame(width: 30, height: 30)
              .overlay(Circle().stroke(.white.opacity(0.92), lineWidth: recipe.textLayers[index].colorHex == color ? 3 : 1))
              .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Text color")
        }

        layerControlButton("Delete", systemImage: "trash", role: .destructive) {
          let removedID = recipe.textLayers[index].id
          recipe.textLayers.remove(at: index)
          if selectedTextID == removedID { selectedTextID = nil }
        }
      }
    }
  }

  private func selectedStickerControls(index: Int) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        layerControlButton("Duplicate", systemImage: "plus.square.on.square") {
          duplicateStickerLayer(at: index)
        }
        layerControlButton("Back", systemImage: "square.2.layers.3d.bottom.filled") {
          updateSticker(at: index) { $0.zIndex -= 1 }
        }
        layerControlButton("Forward", systemImage: "square.2.layers.3d.top.filled") {
          updateSticker(at: index) { $0.zIndex += 1 }
        }
        ForEach(["#FFFFFF", "#111511", "#F7F1E8", "#D8FF40", "#E04F6C"], id: \.self) { color in
          Button {
            updateSticker(at: index) { $0.colorHex = color }
          } label: {
            Circle()
              .fill(Color(uiColor: UIColor(hex: color)))
              .frame(width: 30, height: 30)
              .overlay(Circle().stroke(.white.opacity(0.92), lineWidth: (recipe.stickerLayers ?? [])[index].colorHex == color ? 3 : 1))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Decoration color")
        }
        layerControlButton("Delete", systemImage: "trash", role: .destructive) {
          var layers = recipe.stickerLayers ?? []
          let removedID = layers[index].id
          layers.remove(at: index)
          recipe.stickerLayers = layers
          if selectedStickerID == removedID { selectedStickerID = nil }
        }
      }
    }
  }

  private func layerControlButton(
    _ title: String,
    systemImage: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(inactivePanelColor)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
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

  private var selectedStickerIndex: Int? {
    guard let selectedStickerID else { return nil }
    return (recipe.stickerLayers ?? []).firstIndex(where: { $0.id == selectedStickerID })
  }

  private var selectedTextStyle: MIRANativeTextStyle {
    guard let selectedTextIndex else { return .clean }
    return recipe.textLayers[selectedTextIndex].style ?? .clean
  }

  private var selectedTextBackground: MIRANativeTextBackgroundStyle {
    guard let selectedTextIndex else { return .none }
    return recipe.textLayers[selectedTextIndex].backgroundStyle ?? .none
  }

  private var nextLayerIndex: Int {
    let textMaximum = recipe.textLayers.map(\.zIndex).max() ?? -1
    let stickerMaximum = (recipe.stickerLayers ?? []).map(\.zIndex).max() ?? -1
    return max(textMaximum, stickerMaximum) + 1
  }

  private var selectedChipColor: Color {
    mode == .story ? Color.white : MIRATheme.Color.forest
  }

  private var selectedChipTextColor: Color {
    mode == .story ? MIRATheme.Color.textPrimary : Color.white
  }

  private func stickerBinding(for id: String) -> Binding<MIRANativeStickerLayer> {
    Binding(
      get: {
        (recipe.stickerLayers ?? []).first(where: { $0.id == id }) ?? MIRANativeStickerLayer(id: id, assetType: .star)
      },
      set: { updated in
        var layers = recipe.stickerLayers ?? []
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index] = updated
        recipe.stickerLayers = layers
      }
    )
  }

  private func updateSnapGuides(vertical: Bool, horizontal: Bool) {
    showsVerticalGuide = vertical
    showsHorizontalGuide = horizontal
  }

  private func updateSticker(at index: Int, update: (inout MIRANativeStickerLayer) -> Void) {
    var layers = recipe.stickerLayers ?? []
    guard layers.indices.contains(index) else { return }
    update(&layers[index])
    recipe.stickerLayers = layers
  }

  private func duplicateTextLayer(at index: Int) {
    guard recipe.textLayers.indices.contains(index) else { return }
    var duplicate = recipe.textLayers[index]
    duplicate.id = UUID().uuidString
    duplicate.x = min(0.92, duplicate.x + 0.045)
    duplicate.y = min(0.92, duplicate.y + 0.045)
    duplicate.zIndex = nextLayerIndex
    recipe.textLayers.append(duplicate)
    selectedStickerID = nil
    selectedTextID = duplicate.id
  }

  private func duplicateStickerLayer(at index: Int) {
    var layers = recipe.stickerLayers ?? []
    guard layers.indices.contains(index) else { return }
    var duplicate = layers[index]
    duplicate.id = UUID().uuidString
    duplicate.x = min(0.92, duplicate.x + 0.045)
    duplicate.y = min(0.92, duplicate.y + 0.045)
    duplicate.zIndex = nextLayerIndex
    layers.append(duplicate)
    recipe.stickerLayers = layers
    selectedTextID = nil
    selectedStickerID = duplicate.id
  }

  private func applyDraftText() {
    guard let selectedTextIndex else { return }
    let value = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    let wasPlaceholder = recipe.textLayers[selectedTextIndex].text == "Add text"
    recipe.textLayers[selectedTextIndex].text = value.isEmpty ? "Add text" : value
    if wasPlaceholder {
      switch value.count {
      case 0...12: recipe.textLayers[selectedTextIndex].fontSize = 44
      case 13...34: recipe.textLayers[selectedTextIndex].fontSize = 34
      default: recipe.textLayers[selectedTextIndex].fontSize = 26
      }
    }
  }

  private func editorFont(for style: MIRANativeTextStyle, size: CGFloat) -> Font {
    switch style {
    case .clean: return .system(size: size, weight: .semibold)
    case .editorial: return .custom("Georgia", size: size)
    case .handwritten: return .custom("Marker Felt", size: size)
    case .typewriter: return .custom("Courier", size: size)
    case .bold, .outline: return .system(size: size, weight: .heavy)
    case .cutout: return .system(size: size, weight: .black)
    case .label: return .system(size: size, weight: .bold)
    case .script: return .custom("Snell Roundhand", size: size)
    }
  }
  private var filterPreviewKey: String {
    [
      recipe.selectedFilter.rawValue,
      recipe.aspectRatio.rawValue,
      "\(recipe.brightness)",
      "\(recipe.contrast)",
      "\(recipe.exposure)",
      "\(recipe.warmth)",
      "\(recipe.saturation)",
      "\(recipe.sharpness)",
      "\(recipe.rotationQuarterTurns)",
      "\(media.data.count)"
    ].joined(separator: "-")
  }

  private var availableRatios: [MIRANativeEditorAspectRatio] {
    switch mode {
    case .post:
      return [.portrait3x4, .portrait4x5, .portrait2x3]
    case .story:
      return [.story9x16, .portrait3x4, .portrait4x5, .portrait2x3]
    }
  }

  private var effectiveTrimEnd: Double {
    if recipe.trimEndSeconds > recipe.trimStartSeconds {
      return min(recipe.trimEndSeconds, max(videoDurationSeconds, 0))
    }
    return max(videoDurationSeconds, 0)
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
      let asset = AVURLAsset(url: url)
      let duration = try await asset.load(.duration)
      let seconds = max(0, CMTimeGetSeconds(duration))
      videoDurationSeconds = seconds
      if recipe.trimEndSeconds <= recipe.trimStartSeconds {
        recipe.trimEndSeconds = seconds
      }
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

  private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = max(0, Int(seconds.rounded()))
    return "\(total / 60):\(String(format: "%02d", total % 60))"
  }

  private enum EditorPanel: Hashable {
    case crop
    case text
    case decorate
    case filters
    case adjustments
    case trim

    var title: String {
      switch self {
      case .crop: return "Crop"
      case .text: return "Text"
      case .decorate: return "Decor"
      case .filters: return "Filters"
      case .adjustments: return "Adjust"
      case .trim: return "Trim"
      }
    }

    var systemImage: String {
      switch self {
      case .crop: return "crop.rotate"
      case .text: return "textformat"
      case .decorate: return "wand.and.stars"
      case .filters: return "camera.filters"
      case .adjustments: return "slider.horizontal.3"
      case .trim: return "scissors"
      }
    }
  }
}

private struct MIRAEditableTextLayerView: View {
  @Binding var layer: MIRANativeTextLayer
  let containerSize: CGSize
  let isSelected: Bool
  let onSnapChange: (Bool, Bool) -> Void

  @State private var dragStart: CGPoint?
  @State private var scaleStart: CGFloat?
  @State private var rotationStart: CGFloat?

  var body: some View {
    MIRAEditorTextVisual(layer: layer)
      .frame(maxWidth: containerSize.width * min(max(layer.width ?? 0.76, 0.20), 0.92))
      .contentShape(Rectangle())
      .scaleEffect(layer.scale)
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white.opacity(0.90), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
            .padding(-6)
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
        var x = min(max(dragStart.x + value.translation.width / max(1, containerSize.width), 0.05), 0.95)
        var y = min(max(dragStart.y + value.translation.height / max(1, containerSize.height), 0.05), 0.95)
        let snapsX = abs(x - 0.5) <= 0.018
        let snapsY = abs(y - 0.5) <= 0.018
        if snapsX { x = 0.5 }
        if snapsY { y = 0.5 }
        layer.x = x
        layer.y = y
        onSnapChange(snapsX, snapsY)
      }
      .onEnded { _ in
        dragStart = nil
        onSnapChange(false, false)
      }
  }

  private var scaleGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if scaleStart == nil { scaleStart = layer.scale }
        layer.scale = min(max((scaleStart ?? 1) * value, 0.38), 4.0)
      }
      .onEnded { _ in scaleStart = nil }
  }

  private var rotationGesture: some Gesture {
    RotationGesture()
      .onChanged { value in
        if rotationStart == nil { rotationStart = layer.rotation }
        layer.rotation = (rotationStart ?? 0) + value.radians
      }
      .onEnded { _ in rotationStart = nil }
  }
}

private struct MIRAEditableStickerLayerView: View {
  @Binding var layer: MIRANativeStickerLayer
  let containerSize: CGSize
  let isSelected: Bool
  let onSnapChange: (Bool, Bool) -> Void

  @State private var dragStart: CGPoint?
  @State private var scaleStart: CGFloat?
  @State private var rotationStart: CGFloat?

  var body: some View {
    sticker
      .frame(width: 64, height: 64)
      .foregroundStyle(Color(uiColor: UIColor(hex: layer.colorHex)))
      .opacity(layer.opacity)
      .scaleEffect(layer.scale)
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white.opacity(0.90), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
            .padding(-5)
        }
      }
      .position(x: layer.x * containerSize.width, y: layer.y * containerSize.height)
      .rotationEffect(.radians(layer.rotation))
      .gesture(dragGesture)
      .simultaneousGesture(scaleGesture)
      .simultaneousGesture(rotationGesture)
      .accessibilityLabel(layer.assetType.title)
  }

  @ViewBuilder
  private var sticker: some View {
    if layer.assetType == .tape {
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(Color(uiColor: UIColor(hex: layer.colorHex)).opacity(0.62))
        .frame(width: 82, height: 25)
    } else {
      Image(systemName: layer.assetType.systemImage)
        .font(.system(size: 48, weight: .medium))
        .symbolRenderingMode(.monochrome)
    }
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        if dragStart == nil { dragStart = CGPoint(x: layer.x, y: layer.y) }
        guard let dragStart else { return }
        var x = min(max(dragStart.x + value.translation.width / max(1, containerSize.width), 0.04), 0.96)
        var y = min(max(dragStart.y + value.translation.height / max(1, containerSize.height), 0.04), 0.96)
        let snapsX = abs(x - 0.5) <= 0.018
        let snapsY = abs(y - 0.5) <= 0.018
        if snapsX { x = 0.5 }
        if snapsY { y = 0.5 }
        layer.x = x
        layer.y = y
        onSnapChange(snapsX, snapsY)
      }
      .onEnded { _ in
        dragStart = nil
        onSnapChange(false, false)
      }
  }

  private var scaleGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if scaleStart == nil { scaleStart = layer.scale }
        layer.scale = min(max((scaleStart ?? 1) * value, 0.30), 4.0)
      }
      .onEnded { _ in scaleStart = nil }
  }

  private var rotationGesture: some Gesture {
    RotationGesture()
      .onChanged { value in
        if rotationStart == nil { rotationStart = layer.rotation }
        layer.rotation = (rotationStart ?? 0) + value.radians
      }
      .onEnded { _ in rotationStart = nil }
  }
}

private struct MIRAEditorTextVisual: View {
  let layer: MIRANativeTextLayer

  var body: some View {
    content
      .multilineTextAlignment(layer.swiftUITextAlignment)
      .lineLimit(8)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, resolvedPadding)
      .padding(.vertical, resolvedPadding * 0.58)
      .background { MIRAEditorTextBackground(style: layer.resolvedBackgroundStyle, opacity: layer.backgroundOpacity ?? 0.86) }
      .opacity(min(max(layer.opacity ?? 1, 0.08), 1))
      .shadow(color: .black.opacity(0.28), radius: 7, y: 2)
  }

  @ViewBuilder
  private var content: some View {
    if layer.resolvedStyle == .cutout, layer.text.count <= 28, !layer.text.contains("\n") {
      MIRACutoutEditorText(layer: layer)
    } else if layer.resolvedStyle == .outline {
      MIRAOutlinedEditorText(layer: layer)
    } else {
      Text(layer.text)
        .font(layer.editorFont)
        .foregroundStyle(Color(uiColor: UIColor(hex: layer.colorHex)))
    }
  }

  private var resolvedPadding: CGFloat {
    max(0, min(layer.backgroundPadding ?? 10, 24))
  }
}

private struct MIRAOutlinedEditorText: View {
  let layer: MIRANativeTextLayer

  var body: some View {
    ZStack {
      ForEach(Array(outlineOffsets.enumerated()), id: \.offset) { _, offset in
        Text(layer.text)
          .font(layer.editorFont)
          .foregroundStyle(Color(uiColor: UIColor(hex: layer.colorHex)))
          .offset(x: offset.width, y: offset.height)
      }
      Text(layer.text)
        .font(layer.editorFont)
        .foregroundStyle(Color.black.opacity(0.08))
    }
  }

  private let outlineOffsets = [
    CGSize(width: -1.5, height: 0), CGSize(width: 1.5, height: 0),
    CGSize(width: 0, height: -1.5), CGSize(width: 0, height: 1.5),
    CGSize(width: -1, height: -1), CGSize(width: 1, height: 1)
  ]
}

private struct MIRACutoutEditorText: View {
  let layer: MIRANativeTextLayer

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(layer.text.enumerated()), id: \.offset) { index, character in
        if character.isWhitespace {
          Color.clear.frame(width: 6, height: 1)
        } else {
          let seed = stableHash("\(layer.id)-\(index)-\(character)")
          Text(String(character))
            .font(font(seed: seed))
            .foregroundStyle(Color(uiColor: UIColor(hex: layer.colorHex)))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(paperColor(seed: seed))
            .rotationEffect(.degrees(Double(Int(seed % 9) - 4)))
        }
      }
    }
  }

  private func font(seed: UInt64) -> Font {
    let size = layer.fontSize * (0.84 + CGFloat(seed % 15) / 100)
    switch seed % 4 {
    case 0: return .system(size: size, weight: .black)
    case 1: return .custom("Georgia", size: size)
    case 2: return .custom("Courier", size: size).weight(.bold)
    default: return .custom("Avenir Next", size: size).weight(.heavy)
    }
  }

  private func paperColor(seed: UInt64) -> Color {
    switch seed % 4 {
    case 0: return .white
    case 1: return Color(red: 0.96, green: 0.91, blue: 0.78)
    case 2: return Color(red: 0.84, green: 0.84, blue: 0.82)
    default: return Color(red: 0.90, green: 0.87, blue: 0.78)
    }
  }

  private func stableHash(_ value: String) -> UInt64 {
    value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
      (partial ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }
}

private struct MIRAEditorTextBackground: View {
  let style: MIRANativeTextBackgroundStyle
  let opacity: CGFloat

  @ViewBuilder
  var body: some View {
    switch style {
    case .none:
      Color.clear
    case .highlight:
      Rectangle().fill(Color(red: 0.98, green: 0.85, blue: 0.27).opacity(opacity * 0.86))
    case .paper:
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(Color(red: 0.96, green: 0.93, blue: 0.85).opacity(opacity))
    case .tape:
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(Color(red: 0.91, green: 0.82, blue: 0.62).opacity(opacity * 0.78))
        .rotationEffect(.degrees(-1.2))
    case .label:
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(Color.white.opacity(opacity))
    case .tornPaper:
      MIRATornEditorPaperShape()
        .fill(Color(red: 0.95, green: 0.91, blue: 0.82).opacity(opacity))
    }
  }
}

private struct MIRATornEditorPaperShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let teeth = 10
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + 3))
    for index in 0...teeth {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(teeth)
      path.addLine(to: CGPoint(x: x, y: rect.minY + CGFloat(index % 2) * 3))
    }
    for index in stride(from: teeth, through: 0, by: -1) {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(teeth)
      path.addLine(to: CGPoint(x: x, y: rect.maxY - CGFloat(index % 2) * 3))
    }
    path.closeSubpath()
    return path
  }
}

private struct MIRAEditorTextEntrySheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var text: String
  let onSave: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      HStack {
        Button("Cancel") { dismiss() }
          .foregroundStyle(MIRATheme.Color.textSecondary)
        Spacer()
        Text("Edit text")
          .font(.system(size: 17, weight: .bold))
        Spacer()
        Button("Done") {
          onSave()
          dismiss()
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(MIRATheme.Color.forest)
      }

      TextEditor(text: $text)
        .font(.system(size: 18, weight: .medium))
        .scrollContentBackground(.hidden)
        .padding(12)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
          Text("\(max(0, 280 - text.count))")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .padding(8)
        }
        .onChange(of: text) { _, value in
          if value.count > 280 { text = String(value.prefix(280)) }
        }
    }
    .padding(18)
    .background(MIRATheme.Color.surface)
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

  var resolvedStyle: MIRANativeTextStyle { style ?? .clean }

  var resolvedBackgroundStyle: MIRANativeTextBackgroundStyle {
    let selected = backgroundStyle ?? .none
    return selected == .none && resolvedStyle == .label ? .label : selected
  }

  var editorFont: Font {
    let size = fontSize
    if let fontName { return .custom(fontName, size: size) }
    switch resolvedStyle {
    case .clean: return .custom("Avenir Next", size: size).weight(.semibold)
    case .editorial: return .custom("Georgia", size: size)
    case .handwritten: return .custom("Marker Felt", size: size)
    case .typewriter: return .custom("Courier", size: size).weight(.bold)
    case .bold, .outline: return .system(size: size, weight: .heavy)
    case .cutout: return .system(size: size, weight: .black)
    case .label: return .custom("Avenir Next", size: size).weight(.bold)
    case .script: return .custom("Snell Roundhand", size: size).weight(.bold)
    }
  }
}
