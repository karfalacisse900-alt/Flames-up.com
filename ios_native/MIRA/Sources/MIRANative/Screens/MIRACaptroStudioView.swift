import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit

public struct MIRACaptroStudioView: View {
  private let camera: MIRAWallCamera
  private let api: MIRAAPIClient
  private let onPublish: (MIRACreateWallNoteBody) async throws -> MIRAWallNote

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var document: MIRACaptroStudioDocument?
  @State private var images: [String: UIImage] = [:]
  @State private var selectedLayerID: String?
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var showsObjectTray = false
  @State private var showsTemplateTray = false
  @State private var isPublishing = false
  @State private var publishMessage = ""
  @State private var errorMessage: String?
  @State private var snapGuides = MIRAStudioSnapGuides()
  @FocusState private var isTextEditing: Bool

  public init(
    camera: MIRAWallCamera,
    api: MIRAAPIClient,
    onPublish: @escaping (MIRACreateWallNoteBody) async throws -> MIRAWallNote
  ) {
    self.camera = camera
    self.api = api
    self.onPublish = onPublish
  }

  public var body: some View {
    NavigationStack {
      Group {
        if document == nil {
          templateGallery
            .transition(.opacity)
        } else {
          studioEditor
            .transition(.opacity.combined(with: .scale(scale: 0.99)))
        }
      }
      .background(MIRATheme.Color.launchBackground.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
    }
    .interactiveDismissDisabled(isPublishing)
    .onChange(of: selectedPhotoItem) { _, item in
      guard let item else { return }
      Task { await loadPhoto(item) }
    }
    .miraBottomSheet(isPresented: $showsObjectTray, preferredHeightFraction: 0.48, maxHeight: 470) { close in
      objectTray(close: close)
    }
    .miraBottomSheet(isPresented: $showsTemplateTray, preferredHeightFraction: 0.58, maxHeight: 600) { close in
      compactTemplateTray(close: close)
    }
  }

  private var templateGallery: some View {
    VStack(spacing: 0) {
      studioHeader(
        title: "Captro Studio",
        leadingIcon: "xmark",
        leadingLabel: "Close",
        leadingAction: { dismiss() },
        trailingTitle: nil,
        trailingAction: nil
      )

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 7) {
            Text("Build something worth keeping")
              .font(.system(size: 28, weight: .bold, design: .serif))
              .foregroundStyle(MIRATheme.Color.textPrimary)
            Text("Start with an original layout. Every photo, word, and object stays editable until you post.")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(MIRACaptroStudioTemplate.allCases) { template in
              Button {
                openTemplate(template)
              } label: {
                templateCard(template)
              }
              .buttonStyle(.miraPress)
              .accessibilityLabel("Use \(template.title) template")
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 34)
      }
    }
  }

  private var studioEditor: some View {
    VStack(spacing: 0) {
      studioHeader(
        title: document?.template.title ?? "Captro Studio",
        leadingIcon: "chevron.left",
        leadingLabel: "Templates",
        leadingAction: {
          if hasMeaningfulEdits {
            showsTemplateTray = true
          } else {
            withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
              document = nil
              images = [:]
              selectedLayerID = nil
            }
          }
        },
        trailingTitle: isPublishing ? publishMessage : "Post",
        trailingAction: publishStudioPiece
      )

      GeometryReader { proxy in
        let availableHeight = max(300, proxy.size.height - 170)
        let canvasWidth = min(proxy.size.width - 28, availableHeight * 0.8)
        let canvasHeight = canvasWidth * 1.25

        VStack(spacing: 12) {
          Spacer(minLength: 8)

          if let documentBinding = documentBinding {
            MIRACaptroStudioCanvas(
              document: documentBinding,
              images: images,
              selectedLayerID: $selectedLayerID,
              isEditing: true,
              snapGuides: $snapGuides
            )
            .frame(width: canvasWidth, height: canvasHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
          }

          Spacer(minLength: 6)

          selectedLayerInspector
          addToolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
      }

      if let errorMessage {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.circle.fill")
          Text(errorMessage)
            .lineLimit(2)
          Spacer()
          Button("Dismiss") { self.errorMessage = nil }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.red)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(MIRATheme.Color.surface)
      }
    }
  }

  private func studioHeader(
    title: String,
    leadingIcon: String,
    leadingLabel: String,
    leadingAction: @escaping () -> Void,
    trailingTitle: String?,
    trailingAction: (() -> Void)?
  ) -> some View {
    HStack(spacing: 10) {
      Button(action: leadingAction) {
        Image(systemName: leadingIcon)
          .font(.system(size: 17, weight: .bold))
          .frame(width: 44, height: 44)
          .background(MIRATheme.Color.surfaceSoft, in: Circle())
      }
      .buttonStyle(.miraPress)
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .accessibilityLabel(leadingLabel)

      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)

      Spacer(minLength: 8)

      if let trailingTitle, let trailingAction {
        Button(action: trailingAction) {
          HStack(spacing: 7) {
            if isPublishing { ProgressView().tint(.white) }
            Text(trailingTitle)
              .font(.system(size: 14, weight: .bold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 17)
          .frame(minHeight: 42)
          .background(MIRATheme.Color.forest, in: Capsule())
        }
        .buttonStyle(.miraPress)
        .disabled(isPublishing)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private func templateCard(_ template: MIRACaptroStudioTemplate) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      MIRACaptroStudioCanvas(
        document: .constant(template.makeDocument()),
        images: [:],
        selectedLayerID: .constant(nil),
        isEditing: false,
        snapGuides: .constant(MIRAStudioSnapGuides())
      )
      .aspectRatio(0.8, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .allowsHitTesting(false)

      VStack(alignment: .leading, spacing: 3) {
        Label(template.title, systemImage: template.systemImage)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        Text(template.subtitle)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(2)
      }
    }
    .padding(9)
    .background(MIRATheme.Color.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 17, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 0.8)
    }
  }

  @ViewBuilder
  private var selectedLayerInspector: some View {
    if let selectedLayer {
      VStack(spacing: 8) {
        if selectedLayer.kind == .text {
          HStack(spacing: 8) {
            TextField("Write something", text: selectedTextBinding)
              .focused($isTextEditing)
              .font(.system(size: 14, weight: .medium))
              .padding(.horizontal, 13)
              .frame(height: 42)
              .background(MIRATheme.Color.surfaceSoft, in: Capsule())

            Menu {
              ForEach(MIRACaptroStudioFontStyle.allCases) { style in
                Button(style.title) { updateSelectedLayer { $0.fontStyle = style } }
              }
            } label: {
              Image(systemName: "textformat")
                .frame(width: 42, height: 42)
                .background(MIRATheme.Color.surfaceSoft, in: Circle())
            }
            .foregroundStyle(MIRATheme.Color.textPrimary)
          }
        }

        HStack(spacing: 6) {
          layerAction(title: "Duplicate", icon: "plus.square.on.square", action: duplicateSelectedLayer)
          layerAction(title: "Forward", icon: "square.2.layers.3d.top.filled", action: { moveSelectedLayer(by: 1) })
          layerAction(title: "Back", icon: "square.2.layers.3d.bottom.filled", action: { moveSelectedLayer(by: -1) })
          layerAction(title: "Delete", icon: "trash", isDestructive: true, action: deleteSelectedLayer)
        }
      }
      .padding(.horizontal, 14)
      .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
  }

  private var addToolbar: some View {
    HStack(spacing: 8) {
      PhotosPicker(selection: $selectedPhotoItem, matching: .images, preferredItemEncoding: .current) {
        studioTool(title: "Photo", icon: "photo.badge.plus")
      }
      .buttonStyle(.miraPress)

      Button {
        addTextLayer()
      } label: {
        studioTool(title: "Text", icon: "textformat")
      }
      .buttonStyle(.miraPress)

      Button {
        showsObjectTray = true
      } label: {
        studioTool(title: "Objects", icon: "shippingbox.fill")
      }
      .buttonStyle(.miraPress)

      Button {
        addDateStamp()
      } label: {
        studioTool(title: "Date", icon: "calendar")
      }
      .buttonStyle(.miraPress)
    }
    .padding(.horizontal, 14)
  }

  private func studioTool(title: String, icon: String) -> some View {
    VStack(spacing: 4) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .semibold))
      Text(title)
        .font(.system(size: 10, weight: .bold))
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .frame(maxWidth: .infinity, minHeight: 48)
    .background(MIRATheme.Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 0.8)
    }
  }

  private func layerAction(
    title: String,
    icon: String,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: icon)
          .font(.system(size: 14, weight: .semibold))
        Text(title)
          .font(.system(size: 9, weight: .bold))
      }
      .foregroundStyle(isDestructive ? Color.red : MIRATheme.Color.textPrimary)
      .frame(maxWidth: .infinity, minHeight: 40)
      .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.miraPress)
    .accessibilityLabel(title)
  }

  private func objectTray(close: @escaping () -> Void) -> some View {
    MIRAActionModalCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Physical objects")
              .font(.system(size: 20, weight: .bold, design: .serif))
            Text("Each object becomes a movable layer.")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
          Spacer()
          Button("Done", action: close)
            .font(.system(size: 13, weight: .bold))
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
          ForEach(MIRACaptroStudioObject.allCases) { object in
            Button {
              addObjectLayer(object)
              close()
            } label: {
              VStack(spacing: 7) {
                MIRAStudioObjectVisual(object: object, colorToken: defaultColor(for: object))
                  .frame(width: 48, height: 42)
                Text(object.title)
                  .font(.system(size: 10, weight: .bold))
                  .lineLimit(1)
              }
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity, minHeight: 78)
              .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.miraPress)
          }

          Button {
            addQRCode()
            close()
          } label: {
            VStack(spacing: 7) {
              Image(systemName: "qrcode")
                .font(.system(size: 30, weight: .medium))
              Text("QR card")
                .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
          }
          .buttonStyle(.miraPress)
        }
      }
    }
  }

  private func compactTemplateTray(close: @escaping () -> Void) -> some View {
    MIRAActionModalCard {
      VStack(alignment: .leading, spacing: 13) {
        HStack {
          Text("Choose another template")
            .font(.system(size: 18, weight: .bold, design: .serif))
          Spacer()
          Button("Keep editing", action: close)
            .font(.system(size: 12, weight: .bold))
        }

        ScrollView(showsIndicators: false) {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            ForEach(MIRACaptroStudioTemplate.allCases) { template in
              Button {
                openTemplate(template)
                close()
              } label: {
                Label(template.title, systemImage: template.systemImage)
                  .font(.system(size: 12, weight: .bold))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                  .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                  .padding(.horizontal, 12)
                  .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
              }
              .buttonStyle(.miraPress)
            }
          }
        }
      }
    }
  }

  private var documentBinding: Binding<MIRACaptroStudioDocument>? {
    guard document != nil else { return nil }
    return Binding(
      get: { document ?? MIRACaptroStudioTemplate.blankPaper.makeDocument() },
      set: { document = $0 }
    )
  }

  private var selectedLayer: MIRACaptroStudioLayer? {
    guard let selectedLayerID else { return nil }
    return document?.layers.first(where: { $0.id == selectedLayerID })
  }

  private var selectedTextBinding: Binding<String> {
    Binding(
      get: { selectedLayer?.text ?? "" },
      set: { value in updateSelectedLayer { $0.text = String(value.prefix(180)) } }
    )
  }

  private var hasMeaningfulEdits: Bool {
    guard let document else { return false }
    return !document.layers.filter { $0.kind != .paper }.isEmpty || !images.isEmpty
  }

  private func openTemplate(_ template: MIRACaptroStudioTemplate) {
    withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
      document = template.makeDocument()
      images = [:]
      selectedLayerID = nil
      errorMessage = nil
    }
  }

  @MainActor
  private func loadPhoto(_ item: PhotosPickerItem) async {
    errorMessage = nil
    defer { selectedPhotoItem = nil }
    do {
      guard
        let data = try await item.loadTransferable(type: Data.self),
        let image = await MIRAImageDiskCache.decode(data, maxPixelSize: 2_400)
      else {
        throw MIRAAPIError.server(status: 400, code: "STUDIO_PHOTO_READ_FAILED", detail: "Could not read this photo.")
      }

      guard var document else { return }
      let targetIndex: Int
      if let selectedLayerID,
         let selected = document.layers.firstIndex(where: { $0.id == selectedLayerID && $0.kind == .photo }) {
        targetIndex = selected
      } else if let empty = document.layers.firstIndex(where: { $0.kind == .photo && images[$0.mediaKey ?? ""] == nil }) {
        targetIndex = empty
      } else {
        let layer = MIRACaptroStudioLayer.photo(
          x: 0.5,
          y: 0.5,
          width: 0.62,
          height: 0.48,
          rotation: -0.02,
          zIndex: document.nextZIndex
        )
        document.layers.append(layer)
        targetIndex = document.layers.count - 1
      }

      let key = document.layers[targetIndex].mediaKey ?? UUID().uuidString
      document.layers[targetIndex].mediaKey = key
      images[key] = image
      selectedLayerID = document.layers[targetIndex].id
      self.document = document
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func addTextLayer() {
    guard var document else { return }
    let layer = MIRACaptroStudioLayer.text(
      "Write something",
      x: 0.5,
      y: 0.52,
      width: 0.68,
      zIndex: document.nextZIndex,
      font: .handwritten
    )
    document.layers.append(layer)
    self.document = document
    selectedLayerID = layer.id
    isTextEditing = true
  }

  private func addObjectLayer(_ object: MIRACaptroStudioObject) {
    guard var document else { return }
    let layer = MIRACaptroStudioLayer.object(
      object,
      x: 0.5,
      y: 0.5,
      width: object == .television ? 0.55 : 0.24,
      height: object == .television ? 0.33 : 0.18,
      rotation: object == .paperclip ? 0.25 : -0.035,
      zIndex: document.nextZIndex,
      color: defaultColor(for: object)
    )
    document.layers.append(layer)
    self.document = document
    selectedLayerID = layer.id
  }

  private func addQRCode() {
    guard var document else { return }
    let layer = MIRACaptroStudioLayer.qrCode(
      x: 0.5,
      y: 0.5,
      width: 0.24,
      zIndex: document.nextZIndex,
      value: "https://captro.app"
    )
    document.layers.append(layer)
    self.document = document
    selectedLayerID = layer.id
  }

  private func addDateStamp() {
    guard var document else { return }
    let layer = MIRACaptroStudioLayer.dateStamp(
      x: 0.5,
      y: 0.5,
      width: 0.34,
      zIndex: document.nextZIndex
    )
    document.layers.append(layer)
    self.document = document
    selectedLayerID = layer.id
  }

  private func updateSelectedLayer(_ update: (inout MIRACaptroStudioLayer) -> Void) {
    guard let selectedLayerID, var document,
          let index = document.layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
    update(&document.layers[index])
    self.document = document
  }

  private func duplicateSelectedLayer() {
    guard let selectedLayerID, var document,
          let original = document.layers.first(where: { $0.id == selectedLayerID }) else { return }
    let originalImage = original.mediaKey.flatMap { images[$0] }
    guard let newID = document.duplicateLayer(id: selectedLayerID) else { return }
    if let originalImage,
       let newLayer = document.layers.first(where: { $0.id == newID }),
       let key = newLayer.mediaKey {
      images[key] = originalImage
    }
    self.document = document
    self.selectedLayerID = newID
  }

  private func deleteSelectedLayer() {
    guard let selectedLayerID, var document else { return }
    if let key = document.layers.first(where: { $0.id == selectedLayerID })?.mediaKey {
      images.removeValue(forKey: key)
    }
    document.deleteLayer(id: selectedLayerID)
    self.document = document
    self.selectedLayerID = nil
  }

  private func moveSelectedLayer(by delta: Int) {
    guard let selectedLayerID, var document else { return }
    document.moveLayer(id: selectedLayerID, by: delta)
    self.document = document
  }

  private func defaultColor(for object: MIRACaptroStudioObject) -> String {
    switch object {
    case .tape: return "tape"
    case .paperclip: return "metal"
    case .pushPin: return "red"
    case .ticket: return "butter"
    case .cassette: return "lavender"
    case .television: return "charcoal"
    case .polaroidFrame: return "paper"
    case .passportStamp: return "stamp"
    case .pressedFlower: return "rose"
    case .coffeeStain: return "coffee"
    }
  }

  private func publishStudioPiece() {
    guard let document, !isPublishing else { return }
    selectedLayerID = nil
    snapGuides = MIRAStudioSnapGuides()
    isTextEditing = false
    isPublishing = true
    publishMessage = "Rendering..."
    errorMessage = nil

    Task { @MainActor in
      do {
        let exportView = MIRACaptroStudioExportView(document: document, images: images)
          .frame(width: 1_080, height: 1_350)
        let renderer = ImageRenderer(content: exportView)
        renderer.proposedSize = ProposedViewSize(width: 1_080, height: 1_350)
        renderer.scale = 1
        guard let renderedImage = renderer.uiImage,
              let data = renderedImage.jpegData(compressionQuality: 0.94) else {
          throw MIRAAPIError.server(status: 500, code: "STUDIO_RENDER_FAILED", detail: "Could not render this Studio page.")
        }

        publishMessage = "Checking..."
        let picked = MIRAPickedMedia(
          data: data,
          kind: .image,
          fileName: "captro-studio-\(UUID().uuidString).jpg",
          mimeType: "image/jpeg"
        )
        let uploaded = try await MIRAMediaUploadService(api: api).uploadResult(picked)

        publishMessage = "Posting..."
        let size = MIRAWallNotePresentationResolver.recommendedSize(styleToken: "polaroid", text: "Studio piece", hasMedia: true)
        let request = MIRACreateWallNoteBody(
          wallId: MIRAWallDestination.global.id,
          publishingIdentity: "author",
          body: "",
          category: nil,
          colorToken: "paper",
          styleToken: "polaroid",
          mediaAssetId: uploaded.mediaAssetId,
          mediaUrl: uploaded.url,
          worldX: Double(camera.center.x) - Double(size.width) * 0.5,
          worldY: Double(camera.center.y) - Double(size.height) * 0.5,
          width: Double(size.width),
          height: Double(size.height),
          rotation: 0,
          approximateLocation: nil,
          noteType: "photo",
          backBody: nil,
          backColorToken: nil,
          backStyleToken: nil,
          allowContributions: false,
          voiceMediaId: nil,
          voiceDurationSeconds: nil,
          voiceWaveform: nil,
          location: nil
        )
        _ = try await onPublish(request)
        dismiss()
      } catch {
        isPublishing = false
        publishMessage = ""
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct MIRAStudioSnapGuides: Equatable {
  var vertical = false
  var horizontal = false
}

private struct MIRACaptroStudioExportView: View {
  let document: MIRACaptroStudioDocument
  let images: [String: UIImage]

  var body: some View {
    MIRACaptroStudioCanvas(
      document: .constant(document),
      images: images,
      selectedLayerID: .constant(nil),
      isEditing: false,
      snapGuides: .constant(MIRAStudioSnapGuides())
    )
    .frame(width: 1_080, height: 1_350)
  }
}

private struct MIRACaptroStudioCanvas: View {
  @Binding var document: MIRACaptroStudioDocument
  let images: [String: UIImage]
  @Binding var selectedLayerID: String?
  let isEditing: Bool
  @Binding var snapGuides: MIRAStudioSnapGuides

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        MIRAStudioPaperSurface(token: document.backgroundToken)

        ForEach(document.layers.sorted(by: { $0.zIndex < $1.zIndex })) { layer in
          if let binding = binding(for: layer.id) {
            MIRAStudioEditableLayer(
              layer: binding,
              image: layer.mediaKey.flatMap { images[$0] },
              containerSize: proxy.size,
              isSelected: isEditing && selectedLayerID == layer.id,
              isEditing: isEditing && layer.kind != .paper,
              onSelect: { selectedLayerID = layer.id },
              onSnapChange: { vertical, horizontal in
                snapGuides = MIRAStudioSnapGuides(vertical: vertical, horizontal: horizontal)
              }
            )
            .zIndex(Double(layer.zIndex))
          }
        }

        if isEditing && snapGuides.vertical {
          Rectangle()
            .fill(MIRATheme.Color.accent.opacity(0.72))
            .frame(width: 1)
            .allowsHitTesting(false)
        }
        if isEditing && snapGuides.horizontal {
          Rectangle()
            .fill(MIRATheme.Color.accent.opacity(0.72))
            .frame(height: 1)
            .allowsHitTesting(false)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { if isEditing { selectedLayerID = nil } }
    }
  }

  private func binding(for id: String) -> Binding<MIRACaptroStudioLayer>? {
    guard document.layers.contains(where: { $0.id == id }) else { return nil }
    return Binding(
      get: { document.layers.first(where: { $0.id == id }) ?? document.layers[0] },
      set: { updated in
        guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        document.layers[index] = updated
      }
    )
  }
}

private struct MIRAStudioEditableLayer: View {
  @Binding var layer: MIRACaptroStudioLayer
  let image: UIImage?
  let containerSize: CGSize
  let isSelected: Bool
  let isEditing: Bool
  let onSelect: () -> Void
  let onSnapChange: (Bool, Bool) -> Void

  @State private var dragStart: CGPoint?
  @State private var scaleStart: CGFloat?
  @State private var rotationStart: CGFloat?

  var body: some View {
    MIRAStudioLayerVisual(layer: layer, image: image, containerSize: containerSize)
      .frame(
        width: max(18, layer.width * containerSize.width),
        height: max(18, layer.height * containerSize.height)
      )
      .opacity(layer.opacity)
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(MIRATheme.Color.accent, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            .padding(-5)
        }
      }
      .scaleEffect(layer.scale)
      .rotationEffect(.radians(layer.rotation))
      .position(x: layer.x * containerSize.width, y: layer.y * containerSize.height)
      .contentShape(Rectangle())
      .onTapGesture { if isEditing { onSelect() } }
      .gesture(dragGesture)
      .simultaneousGesture(scaleGesture)
      .simultaneousGesture(rotationGesture)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(isEditing ? "Drag, pinch, or rotate this layer" : "")
  }

  private var accessibilityLabel: String {
    switch layer.kind {
    case .paper: return "Paper background"
    case .photo: return "Photo layer"
    case .text: return layer.text ?? "Text layer"
    case .object: return layer.object?.title ?? "Object layer"
    case .qrCode: return "QR code layer"
    case .dateStamp: return "Date stamp layer"
    }
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        guard isEditing else { return }
        if dragStart == nil { dragStart = CGPoint(x: layer.x, y: layer.y) }
        guard let dragStart else { return }
        let x = MIRACaptroStudioDocument.snappedPosition(
          dragStart.x + value.translation.width / max(1, containerSize.width)
        )
        let y = MIRACaptroStudioDocument.snappedPosition(
          dragStart.y + value.translation.height / max(1, containerSize.height)
        )
        layer.x = x.value
        layer.y = y.value
        onSnapChange(x.snapped, y.snapped)
      }
      .onEnded { _ in
        guard isEditing else { return }
        dragStart = nil
        onSnapChange(false, false)
      }
  }

  private var scaleGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        guard isEditing else { return }
        if scaleStart == nil { scaleStart = layer.scale }
        layer.scale = min(max((scaleStart ?? 1) * value, 0.28), 3.5)
      }
      .onEnded { _ in
        guard isEditing else { return }
        scaleStart = nil
      }
  }

  private var rotationGesture: some Gesture {
    RotationGesture()
      .onChanged { value in
        guard isEditing else { return }
        if rotationStart == nil { rotationStart = layer.rotation }
        layer.rotation = (rotationStart ?? 0) + value.radians
      }
      .onEnded { _ in
        guard isEditing else { return }
        rotationStart = nil
      }
  }
}

private struct MIRAStudioLayerVisual: View {
  let layer: MIRACaptroStudioLayer
  let image: UIImage?
  let containerSize: CGSize

  var body: some View {
    switch layer.kind {
    case .paper:
      MIRAStudioPaperSurface(token: layer.colorToken)

    case .photo:
      ZStack {
        RoundedRectangle(cornerRadius: containerSize.width * 0.012, style: .continuous)
          .fill(Color.white)
          .shadow(color: .black.opacity(0.16), radius: containerSize.width * 0.012, y: containerSize.width * 0.008)
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: containerSize.width * 0.008, style: .continuous))
            .padding(containerSize.width * 0.012)
        } else {
          ZStack {
            MIRAStudioPalette.color("photoPlaceholder")
            Image(systemName: "photo.badge.plus")
              .font(.system(size: max(13, containerSize.width * 0.055), weight: .medium))
              .foregroundStyle(Color.black.opacity(0.30))
          }
          .clipShape(RoundedRectangle(cornerRadius: containerSize.width * 0.008, style: .continuous))
          .padding(containerSize.width * 0.012)
        }
      }
      .clipped()

    case .text:
      Text(layer.text ?? "")
        .font(MIRAStudioTypography.font(layer.fontStyle ?? .handwritten, size: max(10, containerSize.width * 0.058)))
        .foregroundStyle(MIRAStudioPalette.color(layer.colorToken))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.45)
        .lineLimit(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(containerSize.width * 0.006)

    case .object:
      MIRAStudioObjectVisual(object: layer.object ?? .tape, colorToken: layer.colorToken)

    case .qrCode:
      MIRAStudioQRCodeView(value: layer.value ?? "https://captro.app")
        .padding(containerSize.width * 0.012)
        .background(Color.white, in: RoundedRectangle(cornerRadius: containerSize.width * 0.008, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: containerSize.width * 0.01, y: containerSize.width * 0.006)

    case .dateStamp:
      Text(MIRAStudioDateFormatter.displayDate(from: layer.value))
        .font(.system(size: max(9, containerSize.width * 0.032), weight: .bold, design: .monospaced))
        .tracking(containerSize.width * 0.002)
        .foregroundStyle(MIRAStudioPalette.color(layer.colorToken))
        .padding(.horizontal, containerSize.width * 0.015)
        .padding(.vertical, containerSize.width * 0.008)
        .overlay {
          RoundedRectangle(cornerRadius: 4)
            .stroke(MIRAStudioPalette.color(layer.colorToken).opacity(0.72), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
        }
    }
  }
}

private struct MIRAStudioPaperSurface: View {
  let token: String

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(MIRAStudioPalette.color(token)))
      let count = max(12, Int(size.width / 26))
      for index in 0..<count {
        let seed = CGFloat((index * 47) % 97) / 97
        let x = size.width * seed
        let y = size.height * CGFloat((index * 31) % 89) / 89
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: min(size.width, x + size.width * 0.035), y: y + CGFloat(index % 3) - 1))
        context.stroke(path, with: .color(Color.black.opacity(0.025)), lineWidth: max(0.35, size.width * 0.0008))
      }
    }
    .overlay {
      LinearGradient(
        colors: [Color.white.opacity(0.10), Color.clear, Color.black.opacity(0.035)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }
}

private struct MIRAStudioObjectVisual: View {
  let object: MIRACaptroStudioObject
  let colorToken: String

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      switch object {
      case .tape:
        RoundedRectangle(cornerRadius: max(2, size.width * 0.04), style: .continuous)
          .fill(MIRAStudioPalette.color(colorToken).opacity(0.70))
          .overlay {
            Rectangle()
              .fill(Color.white.opacity(0.14))
              .frame(height: max(1, size.height * 0.12))
          }
          .shadow(color: .black.opacity(0.13), radius: size.width * 0.025, y: size.height * 0.08)

      case .paperclip:
        Image(systemName: "paperclip")
          .resizable()
          .scaledToFit()
          .foregroundStyle(
            LinearGradient(colors: [Color.white, MIRAStudioPalette.color(colorToken), Color.white.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
          )
          .shadow(color: .black.opacity(0.22), radius: 2, x: 1, y: 2)

      case .pushPin:
        Image(systemName: "pin.fill")
          .resizable()
          .scaledToFit()
          .foregroundStyle(MIRAStudioPalette.color(colorToken))
          .shadow(color: .black.opacity(0.25), radius: size.width * 0.05, y: size.height * 0.08)

      case .ticket:
        ZStack {
          RoundedRectangle(cornerRadius: size.height * 0.10, style: .continuous)
            .fill(MIRAStudioPalette.color(colorToken))
          HStack(spacing: size.width * 0.06) {
            Image(systemName: "star.fill")
            VStack(spacing: 1) {
              Rectangle().frame(height: max(1, size.height * 0.03))
              Rectangle().frame(height: max(1, size.height * 0.03))
              Rectangle().frame(height: max(1, size.height * 0.03))
            }
          }
          .foregroundStyle(Color.black.opacity(0.55))
          .padding(size.height * 0.18)
        }
        .overlay {
          RoundedRectangle(cornerRadius: size.height * 0.10)
            .stroke(Color.black.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
        }
        .shadow(color: .black.opacity(0.14), radius: 4, y: 3)

      case .cassette:
        ZStack {
          RoundedRectangle(cornerRadius: size.height * 0.10, style: .continuous)
            .fill(MIRAStudioPalette.color(colorToken))
          RoundedRectangle(cornerRadius: size.height * 0.05)
            .fill(Color.white.opacity(0.55))
            .frame(width: size.width * 0.70, height: size.height * 0.44)
          HStack(spacing: size.width * 0.17) {
            Circle().stroke(Color.black.opacity(0.65), lineWidth: max(1, size.width * 0.018))
            Circle().stroke(Color.black.opacity(0.65), lineWidth: max(1, size.width * 0.018))
          }
          .frame(width: size.width * 0.44, height: size.height * 0.25)
          Capsule()
            .fill(Color.black.opacity(0.70))
            .frame(width: size.width * 0.46, height: size.height * 0.09)
            .offset(y: size.height * 0.32)
        }
        .overlay { RoundedRectangle(cornerRadius: size.height * 0.10).stroke(Color.black.opacity(0.26), lineWidth: 1) }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 4)

      case .television:
        ZStack {
          RoundedRectangle(cornerRadius: size.height * 0.12, style: .continuous)
            .fill(MIRAStudioPalette.color(colorToken))
          RoundedRectangle(cornerRadius: size.height * 0.11, style: .continuous)
            .fill(Color.black.opacity(0.76))
            .frame(width: size.width * 0.78, height: size.height * 0.72)
            .offset(x: -size.width * 0.055)
          VStack(spacing: size.height * 0.08) {
            Circle().fill(Color.white.opacity(0.35))
            Circle().fill(Color.white.opacity(0.22))
          }
          .frame(width: size.width * 0.08)
          .offset(x: size.width * 0.40)
        }
        .overlay { RoundedRectangle(cornerRadius: size.height * 0.12).stroke(Color.black.opacity(0.28), lineWidth: 1.2) }
        .shadow(color: .black.opacity(0.22), radius: 7, y: 5)

      case .polaroidFrame:
        Rectangle()
          .fill(Color.white)
          .overlay(alignment: .top) {
            Rectangle()
              .fill(MIRAStudioPalette.color("photoPlaceholder"))
              .padding(size.width * 0.07)
              .padding(.bottom, size.height * 0.25)
          }
          .shadow(color: .black.opacity(0.18), radius: 5, y: 4)

      case .passportStamp:
        ZStack {
          Circle().stroke(MIRAStudioPalette.color(colorToken), lineWidth: max(1.2, size.width * 0.03))
          Circle().stroke(MIRAStudioPalette.color(colorToken).opacity(0.80), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .padding(size.width * 0.10)
          Image(systemName: "airplane")
            .font(.system(size: max(10, size.width * 0.28), weight: .bold))
            .foregroundStyle(MIRAStudioPalette.color(colorToken))
        }
        .opacity(0.78)

      case .pressedFlower:
        Image(systemName: "camera.macro")
          .resizable()
          .scaledToFit()
          .foregroundStyle(MIRAStudioPalette.color(colorToken).opacity(0.82))
          .shadow(color: .black.opacity(0.13), radius: 2, y: 2)

      case .coffeeStain:
        ZStack {
          Circle().stroke(MIRAStudioPalette.color(colorToken).opacity(0.45), lineWidth: max(2, size.width * 0.05))
          Circle().stroke(MIRAStudioPalette.color(colorToken).opacity(0.20), lineWidth: max(1, size.width * 0.02))
            .padding(size.width * 0.08)
        }
        .blur(radius: max(0.2, size.width * 0.006))
      }
    }
  }
}

private struct MIRAStudioQRCodeView: View {
  let value: String

  var body: some View {
    if let image = MIRAStudioQRCodeCache.shared.image(for: value) {
      Image(uiImage: image)
        .resizable()
        .interpolation(.none)
        .scaledToFit()
        .accessibilityLabel("QR code")
    } else {
      Image(systemName: "qrcode")
        .resizable()
        .scaledToFit()
    }
  }
}

private final class MIRAStudioQRCodeCache {
  static let shared = MIRAStudioQRCodeCache()
  private let cache = NSCache<NSString, UIImage>()
  private let context = CIContext(options: [.useSoftwareRenderer: false])

  func image(for value: String) -> UIImage? {
    let key = value as NSString
    if let cached = cache.object(forKey: key) { return cached }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(value.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
          let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
    let image = UIImage(cgImage: cgImage)
    cache.setObject(image, forKey: key)
    return image
  }
}

private enum MIRAStudioTypography {
  static func font(_ style: MIRACaptroStudioFontStyle, size: CGFloat) -> Font {
    switch style {
    case .modern: return .system(size: size, weight: .bold)
    case .editorial: return .custom("Georgia", size: size)
    case .handwritten: return .custom("Marker Felt", size: size)
    case .typewriter: return .custom("Courier", size: size).weight(.bold)
    case .cutout: return .system(size: size, weight: .black, design: .rounded)
    case .script: return .custom("Snell Roundhand", size: size)
    }
  }
}

private enum MIRAStudioDateFormatter {
  static func displayDate(from value: String?) -> String {
    guard let value, let date = ISO8601DateFormatter().date(from: value) else {
      return Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }
    return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
  }
}

private enum MIRAStudioPalette {
  static func color(_ token: String) -> Color {
    switch token {
    case "warmPaper", "paper", "photoPaper": return Color(red: 0.965, green: 0.944, blue: 0.895)
    case "sagePaper": return Color(red: 0.835, green: 0.846, blue: 0.775)
    case "lilacPaper": return Color(red: 0.875, green: 0.845, blue: 0.895)
    case "schoolPaper": return Color(red: 0.930, green: 0.918, blue: 0.875)
    case "kraftPaper": return Color(red: 0.770, green: 0.660, blue: 0.500)
    case "travelPaper": return Color(red: 0.900, green: 0.830, blue: 0.665)
    case "charcoalPaper", "charcoal": return Color(red: 0.185, green: 0.175, blue: 0.170)
    case "ink": return Color(red: 0.085, green: 0.078, blue: 0.068)
    case "forest": return Color(red: 0.115, green: 0.235, blue: 0.135)
    case "tape": return Color(red: 0.930, green: 0.840, blue: 0.565)
    case "metal": return Color(red: 0.650, green: 0.665, blue: 0.670)
    case "red": return Color(red: 0.790, green: 0.190, blue: 0.125)
    case "butter": return Color(red: 0.965, green: 0.835, blue: 0.390)
    case "lavender": return Color(red: 0.600, green: 0.565, blue: 0.740)
    case "stamp": return Color(red: 0.365, green: 0.145, blue: 0.125)
    case "rose": return Color(red: 0.740, green: 0.360, blue: 0.430)
    case "coffee": return Color(red: 0.360, green: 0.205, blue: 0.105)
    case "sky": return Color(red: 0.590, green: 0.795, blue: 0.850)
    case "photoPlaceholder": return Color(red: 0.800, green: 0.790, blue: 0.750)
    default: return Color(red: 0.965, green: 0.944, blue: 0.895)
    }
  }
}
