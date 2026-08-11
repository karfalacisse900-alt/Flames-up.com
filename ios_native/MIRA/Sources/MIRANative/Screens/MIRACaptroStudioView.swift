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
  @State private var selectedPhotoItems: [PhotosPickerItem] = []
  @State private var showsObjectTray = false
  @State private var showsTemplateTray = false
  @State private var showsDocumentPreview = false
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
    .onChange(of: selectedPhotoItems) { _, items in
      guard !items.isEmpty else { return }
      Task { await loadPhotos(items) }
    }
    .miraBottomSheet(isPresented: $showsObjectTray, preferredHeightFraction: 0.48, maxHeight: 470) { close in
      objectTray(close: close)
    }
    .miraBottomSheet(isPresented: $showsTemplateTray, preferredHeightFraction: 0.58, maxHeight: 600) { close in
      compactTemplateTray(close: close)
    }
    .fullScreenCover(isPresented: $showsDocumentPreview) {
      documentPreview
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
            ForEach(MIRACaptroStudioTemplate.creationTemplates) { template in
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
        secondaryTrailingIcon: "eye",
        secondaryTrailingLabel: "Preview note",
        secondaryTrailingAction: { showsDocumentPreview = true },
        trailingTitle: isPublishing ? publishMessage : "Post",
        trailingAction: publishStudioPiece
      )

      GeometryReader { proxy in
        let availableHeight = max(300, proxy.size.height - 170)
        let draftCanvas = document.map(makeDraftNoteCanvas)
        let canvasAspectRatio = CGFloat(draftCanvas?.aspectRatio ?? 0.8)
        let canvasWidth = min(proxy.size.width - 28, availableHeight * canvasAspectRatio)
        let canvasHeight = canvasWidth / max(0.25, canvasAspectRatio)

        VStack(spacing: 12) {
          Spacer(minLength: 8)

          if let documentBinding = documentBinding {
            MIRACaptroStudioCanvas(
              document: documentBinding,
              canvas: makeDraftNoteCanvas(document: documentBinding.wrappedValue),
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

  @ViewBuilder
  private var documentPreview: some View {
    ZStack(alignment: .topLeading) {
      Color(red: 0.055, green: 0.052, blue: 0.048)
        .ignoresSafeArea()

      if let document {
        GeometryReader { proxy in
          let canvas = makeDraftNoteCanvas(document: document)
          let width = proxy.size.width
          let height = width * CGFloat(canvas.designHeight / max(1, canvas.designWidth))

          ScrollView(showsIndicators: false) {
            MIRANoteCanvasRenderer(
              canvas: canvas,
              mode: .detail,
              localImages: images
            )
            .frame(width: width, height: height)
            .accessibilityLabel("Full note preview")
          }
          .background(Color(red: 0.055, green: 0.052, blue: 0.048))
        }
      }

      Button {
        showsDocumentPreview = false
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 46, height: 46)
          .background(.black.opacity(0.62), in: Circle())
          .overlay { Circle().stroke(.white.opacity(0.16), lineWidth: 0.8) }
      }
      .buttonStyle(.miraPress)
      .padding(.leading, 16)
      .padding(.top, 12)
      .accessibilityLabel("Close preview")
    }
    .miraStatusBarHidden(true)
  }

  private func studioHeader(
    title: String,
    leadingIcon: String,
    leadingLabel: String,
    leadingAction: @escaping () -> Void,
    secondaryTrailingIcon: String? = nil,
    secondaryTrailingLabel: String? = nil,
    secondaryTrailingAction: (() -> Void)? = nil,
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

      if let secondaryTrailingIcon, let secondaryTrailingAction {
        Button(action: secondaryTrailingAction) {
          Image(systemName: secondaryTrailingIcon)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 42, height: 42)
            .background(MIRATheme.Color.surfaceSoft, in: Circle())
        }
        .buttonStyle(.miraPress)
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .accessibilityLabel(secondaryTrailingLabel ?? "More")
      }

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
        canvas: makeDraftNoteCanvas(document: template.makeDocument()),
        images: [:],
        selectedLayerID: .constant(nil),
        isEditing: false,
        snapGuides: .constant(MIRAStudioSnapGuides())
      )
      .aspectRatio(
        CGFloat(1_080 / template.canvasDesignHeight),
        contentMode: .fit
      )
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

        if selectedLayer.kind == .photo {
          VStack(spacing: 7) {
            Picker("Frame", selection: selectedPhotoFrameBinding) {
              ForEach(MIRACaptroStudioPhotoFrame.allCases) { frame in
                Text(frame.title).tag(frame)
              }
            }
            .pickerStyle(.segmented)

            HStack {
              Label("Crop", systemImage: "crop")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MIRATheme.Color.textPrimary)
              Spacer()
              Button("Reset") {
                updateSelectedLayer {
                  $0.cropX = 0.5
                  $0.cropY = 0.5
                  $0.cropScale = 1
                }
              }
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(MIRATheme.Color.forest)
            }

            HStack(spacing: 9) {
              Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
              Slider(value: selectedCropBinding(\.cropScale, default: 1), in: 1...3)
                .tint(MIRATheme.Color.forest)
              Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
            }
            HStack(spacing: 9) {
              Image(systemName: "arrow.left.and.right")
                .font(.system(size: 11, weight: .semibold))
              Slider(value: selectedCropBinding(\.cropX, default: 0.5), in: 0...1)
                .tint(MIRATheme.Color.forest)
              Image(systemName: "arrow.up.and.down")
                .font(.system(size: 11, weight: .semibold))
              Slider(value: selectedCropBinding(\.cropY, default: 0.5), in: 0...1)
                .tint(MIRATheme.Color.forest)
            }
          }
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        HStack(spacing: 6) {
          layerAction(title: selectedLayer.isLocked == true ? "Unlock" : "Lock", icon: selectedLayer.isLocked == true ? "lock.open" : "lock", action: toggleSelectedLayerLock)
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
      PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 12, matching: .images, preferredItemEncoding: .current) {
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
            ForEach(MIRACaptroStudioTemplate.creationTemplates) { template in
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

  private var selectedPhotoFrameBinding: Binding<MIRACaptroStudioPhotoFrame> {
    Binding(
      get: { selectedLayer?.photoFrame ?? .polaroid },
      set: { frame in updateSelectedLayer { $0.photoFrame = frame } }
    )
  }

  private func selectedCropBinding(
    _ keyPath: WritableKeyPath<MIRACaptroStudioLayer, CGFloat?>,
    default defaultValue: CGFloat
  ) -> Binding<CGFloat> {
    Binding(
      get: { selectedLayer?[keyPath: keyPath] ?? defaultValue },
      set: { value in
        updateSelectedLayer { layer in
          layer[keyPath: keyPath] = value
        }
      }
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
  private func loadPhotos(_ items: [PhotosPickerItem]) async {
    errorMessage = nil
    defer { selectedPhotoItems = [] }
    do {
      for (offset, item) in items.prefix(12).enumerated() {
        guard
          let data = try await item.loadTransferable(type: Data.self),
          let image = await MIRAImageDiskCache.decode(data, maxPixelSize: 2_400)
        else {
          throw MIRAAPIError.server(status: 400, code: "STUDIO_PHOTO_READ_FAILED", detail: "Could not read one of these photos.")
        }

        guard var currentDocument = document else { return }
        let targetIndex: Int
        if items.count == 1,
           let selectedLayerID,
           let selected = currentDocument.layers.firstIndex(where: { $0.id == selectedLayerID && $0.kind == .photo }) {
          targetIndex = selected
        } else if let empty = currentDocument.layers.firstIndex(where: { $0.kind == .photo && images[$0.mediaKey ?? ""] == nil }) {
          targetIndex = empty
        } else {
          let columnOffset = CGFloat((offset % 3) - 1) * 0.09
          let rowOffset = CGFloat(offset % 4) * 0.055
          let layer = MIRACaptroStudioLayer.photo(
            x: min(0.82, max(0.18, 0.5 + columnOffset)),
            y: min(0.82, 0.42 + rowOffset),
            width: 0.58,
            height: 0.43,
            rotation: CGFloat((offset % 3) - 1) * 0.035,
            zIndex: currentDocument.nextZIndex,
            frame: .print
          )
          currentDocument.layers.append(layer)
          targetIndex = currentDocument.layers.count - 1
        }

        let key = currentDocument.layers[targetIndex].mediaKey ?? UUID().uuidString
        currentDocument.layers[targetIndex].mediaKey = key
        images[key] = image
        selectedLayerID = currentDocument.layers[targetIndex].id
        document = currentDocument
      }
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
    let objectSize: CGSize
    switch object {
    case .tornPaper:
      objectSize = CGSize(width: 0.58, height: 0.24)
    case .texturedPaper:
      objectSize = CGSize(width: 0.60, height: 0.34)
    case .handDrawnArrow:
      objectSize = CGSize(width: 0.34, height: 0.17)
    case .organicShape:
      objectSize = CGSize(width: 0.30, height: 0.23)
    case .television:
      objectSize = CGSize(width: 0.55, height: 0.33)
    case .tape:
      objectSize = CGSize(width: 0.34, height: 0.075)
    default:
      objectSize = CGSize(width: 0.24, height: 0.18)
    }
    let layer = MIRACaptroStudioLayer.object(
      object,
      x: 0.5,
      y: 0.5,
      width: objectSize.width,
      height: objectSize.height,
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
    guard let selectedLayerID, var document else { return }
    guard let newID = document.duplicateLayer(id: selectedLayerID) else { return }
    self.document = document
    self.selectedLayerID = newID
  }

  private func deleteSelectedLayer() {
    guard let selectedLayerID, var document else { return }
    let removedMediaKey = document.layers.first(where: { $0.id == selectedLayerID })?.mediaKey
    document.deleteLayer(id: selectedLayerID)
    if let removedMediaKey,
       !document.layers.contains(where: { $0.mediaKey == removedMediaKey }) {
      images.removeValue(forKey: removedMediaKey)
    }
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
    case .tornPaper: return "paper"
    case .texturedPaper: return "schoolPaper"
    case .handDrawnArrow: return "ink"
    case .organicShape: return "rose"
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
    publishMessage = "Preparing..."
    errorMessage = nil

    Task { @MainActor in
      do {
        let uploads = try await uploadStudioImages(document: document)
        let canvas = makeNoteCanvas(document: document, uploads: uploads)
        guard !canvas.elements.isEmpty else {
          throw MIRAAPIError.server(
            status: 422,
            code: "EMPTY_NOTE_CANVAS",
            detail: "Add writing, a photo, or a decoration before publishing."
          )
        }
        let firstUpload = uploads.values.first
        let canvasText = canvas.elements
          .compactMap(\.text)
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .joined(separator: "\n")

        publishMessage = "Posting..."
        let size = CGSize(width: 340, height: 425)
        let request = MIRACreateWallNoteBody(
          wallId: MIRAWallDestination.global.id,
          publishingIdentity: "author",
          body: canvasText,
          category: nil,
          colorToken: document.backgroundToken,
          styleToken: "canvas",
          mediaAssetId: firstUpload?.mediaAssetId,
          mediaUrl: firstUpload?.url,
          worldX: Double(camera.center.x) - Double(size.width) * 0.5,
          worldY: Double(camera.center.y) - Double(size.height) * 0.5,
          width: Double(size.width),
          height: Double(size.height),
          rotation: 0,
          approximateLocation: nil,
          noteType: uploads.isEmpty ? "text" : "photo",
          backBody: nil,
          backColorToken: nil,
          backStyleToken: nil,
          allowContributions: false,
          voiceMediaId: nil,
          voiceDurationSeconds: nil,
          voiceWaveform: nil,
          location: nil,
          canvas: canvas
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

  @MainActor
  private func uploadStudioImages(
    document: MIRACaptroStudioDocument
  ) async throws -> [String: MIRAMediaUploadResult] {
    let mediaKeys = Array(Set(
      document.layers
        .filter { $0.kind == .photo }
        .compactMap(\.mediaKey)
        .filter { images[$0] != nil }
    )).sorted()
    guard !mediaKeys.isEmpty else { return [:] }

    let uploader = MIRAMediaUploadService(api: api)
    var uploaded: [String: MIRAMediaUploadResult] = [:]
    for (index, key) in mediaKeys.enumerated() {
      guard let image = images[key],
            let data = image.jpegData(compressionQuality: 0.94) else {
        throw MIRAAPIError.server(
          status: 500,
          code: "STUDIO_IMAGE_ENCODING_FAILED",
          detail: "One of the photos could not be prepared."
        )
      }
      publishMessage = "Uploading \(index + 1) of \(mediaKeys.count)..."
      let picked = MIRAPickedMedia(
        data: data,
        kind: .image,
        fileName: "captro-canvas-\(UUID().uuidString).jpg",
        mimeType: "image/jpeg"
      )
      uploaded[key] = try await uploader.uploadResult(picked)
    }
    return uploaded
  }

  private func makeNoteCanvas(
    document: MIRACaptroStudioDocument,
    uploads: [String: MIRAMediaUploadResult]
  ) -> MIRANoteCanvas {
    let designHeight = document.template.canvasDesignHeight
    buildNoteCanvas(document: document) { layer in
      makeCanvasElement(
        layer,
        upload: layer.mediaKey.flatMap { uploads[$0] },
        designHeight: designHeight
      )
    }
  }

  private func makeDraftNoteCanvas(document: MIRACaptroStudioDocument) -> MIRANoteCanvas {
    let designHeight = document.template.canvasDesignHeight
    buildNoteCanvas(document: document) { layer in
      makeCanvasElement(
        layer,
        upload: nil,
        localMediaKey: layer.kind == .photo ? layer.mediaKey : nil,
        designHeight: designHeight
      )
    }
  }

  private func buildNoteCanvas(
    document: MIRACaptroStudioDocument,
    elementBuilder: (MIRACaptroStudioLayer) -> MIRANoteCanvasElement?
  ) -> MIRANoteCanvas {
    MIRANoteCanvas(
      template: document.template.noteCanvasTemplate,
      designWidth: 1_080,
      designHeight: document.template.canvasDesignHeight,
      background: canvasBackground(for: document.backgroundToken),
      elements: document.layers.compactMap(elementBuilder)
    )
  }

  private func makeCanvasElement(
    _ layer: MIRACaptroStudioLayer,
    upload: MIRAMediaUploadResult?,
    localMediaKey: String? = nil,
    designHeight: Double
  ) -> MIRANoteCanvasElement? {
    guard layer.kind != .paper else { return nil }
    let kind: MIRANoteCanvasElementKind
    var style = MIRANoteCanvasElementStyle(
      colorHex: canvasColorHex(layer.colorToken),
      shadowLevel: layer.kind == .text ? 0 : 2
    )
    var mediaAssetID: String?
    var mediaURL: String?

    switch layer.kind {
    case .paper:
      return nil
    case .photo:
      guard upload != nil || localMediaKey != nil else { return nil }
      let isPolaroid = (layer.photoFrame ?? .polaroid) == .polaroid
      kind = isPolaroid ? .polaroid : .photo
      mediaAssetID = upload?.mediaAssetId ?? localMediaKey
      mediaURL = upload?.url
      style.material = "photographic_print"
      style.cornerRadius = isPolaroid ? 2 : 0
      style.borderWidth = isPolaroid ? 14 : 0
      style.borderColorHex = "#F8F5EC"
    case .text:
      kind = (layer.fontStyle == .handwritten || layer.fontStyle == .script)
        ? .handwrittenCaption
        : .text
      style.fontName = canvasFontName(layer.fontStyle ?? .handwritten)
      style.fontSize = min(180, max(22, Double(layer.height) * designHeight * 0.32))
      style.fontWeight = layer.fontStyle == .cutout ? "heavy" : "regular"
      style.textAlignment = .center
    case .object:
      switch layer.object {
      case .tornPaper:
        kind = .tornPaper
        style.material = "crumpled_paper"
        style.shadowLevel = 1
      case .texturedPaper:
        kind = .texturedPaper
        style.material = "cotton_paper"
        style.shadowLevel = 1
      case .handDrawnArrow:
        kind = .drawing
        style.drawingName = "hand_drawn_arrow"
        style.shadowLevel = 0
      case .organicShape:
        kind = .shape
        style.shapeName = "organic_blob"
        style.shadowLevel = 1
      case .tape:
        kind = .tape
        style.material = "translucent_tape"
      case .pressedFlower:
        kind = .flower
      default:
        kind = .sticker
        style.stickerName = layer.object?.rawValue
      }
    case .qrCode:
      kind = .sticker
      style.stickerName = "qrcode"
    case .dateStamp:
      kind = .text
      style.fontName = "AmericanTypewriter"
      style.fontSize = min(90, max(18, Double(layer.height) * designHeight * 0.42))
      style.fontWeight = "semibold"
      style.textAlignment = .center
    }

    let renderedWidth = min(1.5, max(0.02, Double(layer.width * layer.scale)))
    let renderedHeight = min(1.5, max(0.02, Double(layer.height * layer.scale)))
    let text: String?
    switch layer.kind {
    case .dateStamp:
      text = MIRAStudioDateFormatter.displayDate(from: layer.value)
    case .qrCode:
      text = layer.value
    default:
      text = layer.text
    }
    return MIRANoteCanvasElement(
      id: layer.id,
      kind: kind,
      x: min(1.5, max(-0.5, Double(layer.x))),
      y: min(1.5, max(-0.5, Double(layer.y))),
      width: renderedWidth,
      height: renderedHeight,
      rotation: Double(layer.rotation) * 180 / Double.pi,
      zIndex: layer.zIndex,
      opacity: min(1, max(0, Double(layer.opacity))),
      isLocked: layer.isLocked == true,
      text: text,
      mediaAssetId: mediaAssetID,
      mediaUrl: mediaURL,
      thumbnailUrl: nil,
      cropX: Double(layer.cropX ?? 0.5),
      cropY: Double(layer.cropY ?? 0.5),
      cropScale: Double(layer.cropScale ?? 1),
      style: style
    )
  }

  private func canvasBackground(for token: String) -> MIRANoteCanvasBackground {
    switch token {
    case "sagePaper": return MIRANoteCanvasBackground(material: "linen", colorHex: "#DCE3D3", textureAsset: "CaptroLinenBoard")
    case "lilacPaper": return MIRANoteCanvasBackground(material: "cotton_paper", colorHex: "#E7DFEB", textureAsset: "CaptroArchivalPaper")
    case "schoolPaper": return MIRANoteCanvasBackground(material: "notebook_paper", colorHex: "#F2EAD8", textureAsset: "CaptroArchivalPaper")
    case "kraftPaper": return MIRANoteCanvasBackground(material: "kraft_paper", colorHex: "#C8A477", textureAsset: "CaptroArchivalPaper")
    case "travelPaper": return MIRANoteCanvasBackground(material: "aged_paper", colorHex: "#EFE0BF", textureAsset: "CaptroArchivalPaper")
    case "charcoalPaper": return MIRANoteCanvasBackground(material: "fabric", colorHex: "#171614", textureAsset: "CaptroLinenBoard")
    case "recipePaper": return MIRANoteCanvasBackground(material: "cotton_paper", colorHex: "#F4EBDD", textureAsset: "CaptroArchivalPaper")
    default: return MIRANoteCanvasBackground(material: "cotton_paper", colorHex: "#F4F0E7", textureAsset: "CaptroArchivalPaper")
    }
  }

  private func canvasColorHex(_ token: String) -> String {
    switch token {
    case "paper", "ink": return "#171410"
    case "white": return "#FFFFFF"
    case "rust", "red": return "#9A382C"
    case "sage": return "#61715A"
    case "rose": return "#B65D69"
    case "lavender": return "#7D6D91"
    case "butter": return "#D6AC48"
    case "charcoal": return "#24211E"
    case "stamp": return "#4C5E72"
    case "coffee": return "#72513B"
    case "metal": return "#76736D"
    case "tape": return "#E8D9AE"
    default: return "#171410"
    }
  }

  private func canvasFontName(_ style: MIRACaptroStudioFontStyle) -> String {
    switch style {
    case .modern: return "AvenirNext-Regular"
    case .editorial: return "NewYork-Regular"
    case .handwritten: return "Noteworthy"
    case .typewriter: return "AmericanTypewriter"
    case .cutout: return "AvenirNext-Heavy"
    case .script: return "SnellRoundhand"
    }
  }
}

private struct MIRAStudioSnapGuides: Equatable {
  var vertical = false
  var horizontal = false
}

private struct MIRACaptroStudioCanvas: View {
  @Binding var document: MIRACaptroStudioDocument
  let canvas: MIRANoteCanvas
  let images: [String: UIImage]
  @Binding var selectedLayerID: String?
  let isEditing: Bool
  @Binding var snapGuides: MIRAStudioSnapGuides

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            if isEditing { selectedLayerID = nil }
          }

        MIRANoteCanvasRenderer(
          canvas: canvas,
          mode: isEditing ? .editor : .wallPreview,
          localImages: images
        )
        .frame(width: proxy.size.width, height: proxy.size.height)
        .allowsHitTesting(false)

        ForEach(document.layers.sorted(by: { $0.zIndex < $1.zIndex })) { layer in
          if layer.kind != .paper, let binding = binding(for: layer.id) {
            MIRAStudioEditableLayer(
              layer: binding,
              image: layer.mediaKey.flatMap { images[$0] },
              containerSize: proxy.size,
              rendersContent: false,
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
  let rendersContent: Bool
  let isSelected: Bool
  let isEditing: Bool
  let onSelect: () -> Void
  let onSnapChange: (Bool, Bool) -> Void

  @State private var dragStart: CGPoint?
  @State private var scaleStart: CGFloat?
  @State private var rotationStart: CGFloat?

  var body: some View {
    Group {
      if rendersContent {
        MIRAStudioLayerVisual(layer: layer, image: image, containerSize: containerSize)
      } else {
        Color.clear
      }
    }
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
      .accessibilityHint(
        isEditing
          ? (layer.isLocked == true ? "Unlock this layer to move or resize it" : "Drag, pinch, or rotate this layer")
          : ""
      )
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
        guard isEditing, layer.isLocked != true else { return }
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
        guard isEditing, layer.isLocked != true else { return }
        dragStart = nil
        onSnapChange(false, false)
      }
  }

  private var scaleGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        guard isEditing, layer.isLocked != true else { return }
        if scaleStart == nil { scaleStart = layer.scale }
        layer.scale = min(max((scaleStart ?? 1) * value, 0.28), 3.5)
      }
      .onEnded { _ in
        guard isEditing, layer.isLocked != true else { return }
        scaleStart = nil
      }
  }

  private var rotationGesture: some Gesture {
    RotationGesture()
      .onChanged { value in
        guard isEditing, layer.isLocked != true else { return }
        if rotationStart == nil { rotationStart = layer.rotation }
        layer.rotation = (rotationStart ?? 0) + value.radians
      }
      .onEnded { _ in
        guard isEditing, layer.isLocked != true else { return }
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
      GeometryReader { proxy in
        let isPolaroid = (layer.photoFrame ?? .polaroid) == .polaroid
        let inset = isPolaroid ? max(4, containerSize.width * 0.012) : 0
        let photoSize = CGSize(
          width: max(1, proxy.size.width - (inset * 2)),
          height: max(1, proxy.size.height - (inset * 2))
        )
        let cropOffset = CGSize(
          width: ((layer.cropX ?? 0.5) - 0.5) * photoSize.width,
          height: ((layer.cropY ?? 0.5) - 0.5) * photoSize.height
        )

        ZStack {
          if isPolaroid {
            RoundedRectangle(cornerRadius: containerSize.width * 0.012, style: .continuous)
              .fill(Color(red: 0.975, green: 0.965, blue: 0.925))
              .shadow(
                color: .black.opacity(0.16),
                radius: containerSize.width * 0.012,
                y: containerSize.width * 0.008
              )
          }

          Group {
            if let image {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: photoSize.width, height: photoSize.height)
                .scaleEffect(max(1, layer.cropScale ?? 1))
                .offset(cropOffset)
            } else {
              ZStack {
                MIRAStudioPalette.color("photoPlaceholder")
                Image(systemName: "photo.badge.plus")
                  .font(.system(size: max(13, containerSize.width * 0.055), weight: .medium))
                  .foregroundStyle(Color.black.opacity(0.30))
              }
              .frame(width: photoSize.width, height: photoSize.height)
            }
          }
          .frame(width: photoSize.width, height: photoSize.height)
          .clipShape(RoundedRectangle(cornerRadius: isPolaroid ? containerSize.width * 0.008 : 1, style: .continuous))
          .overlay { CaptroPhotoPrintFinish(seed: layer.id) }
          .shadow(
            color: isPolaroid ? .clear : .black.opacity(0.18),
            radius: isPolaroid ? 0 : containerSize.width * 0.012,
            y: isPolaroid ? 0 : containerSize.width * 0.009
          )
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
      case .tornPaper:
        ZStack {
          MIRAStudioTornPaperShape()
            .fill(MIRAStudioPalette.color(colorToken))
          CaptroPhotographedPaper(
            seed: "studio-torn-\(colorToken)",
            kind: .archival,
            base: MIRAStudioPalette.color(colorToken),
            textureOpacity: 0.34,
            directionalLight: 0.13
          )
          .clipShape(MIRAStudioTornPaperShape())
        }
        .shadow(color: .black.opacity(0.13), radius: max(2, size.width * 0.025), y: max(2, size.height * 0.035))

      case .texturedPaper:
        CaptroPhotographedPaper(
          seed: "studio-paper-\(colorToken)",
          kind: colorToken == "schoolPaper" ? .notebook : .linen,
          base: MIRAStudioPalette.color(colorToken),
          textureOpacity: 0.42,
          directionalLight: 0.16
        )
        .overlay {
          Rectangle().stroke(Color.black.opacity(0.08), lineWidth: max(0.5, size.width * 0.002))
        }
        .shadow(color: .black.opacity(0.12), radius: max(2, size.width * 0.022), y: max(2, size.height * 0.03))

      case .handDrawnArrow:
        Canvas { context, canvasSize in
          var stroke = Path()
          stroke.move(to: CGPoint(x: canvasSize.width * 0.08, y: canvasSize.height * 0.76))
          stroke.addCurve(
            to: CGPoint(x: canvasSize.width * 0.83, y: canvasSize.height * 0.28),
            control1: CGPoint(x: canvasSize.width * 0.34, y: canvasSize.height * 0.92),
            control2: CGPoint(x: canvasSize.width * 0.56, y: canvasSize.height * 0.18)
          )
          stroke.move(to: CGPoint(x: canvasSize.width * 0.65, y: canvasSize.height * 0.20))
          stroke.addLine(to: CGPoint(x: canvasSize.width * 0.84, y: canvasSize.height * 0.28))
          stroke.addLine(to: CGPoint(x: canvasSize.width * 0.76, y: canvasSize.height * 0.54))
          context.stroke(
            stroke,
            with: .color(MIRAStudioPalette.color(colorToken)),
            style: StrokeStyle(lineWidth: max(2, canvasSize.width * 0.018), lineCap: .round, lineJoin: .round)
          )
        }

      case .organicShape:
        MIRAStudioOrganicShape()
          .fill(MIRAStudioPalette.color(colorToken).opacity(0.88))
          .overlay {
            MIRAStudioOrganicShape()
              .stroke(Color.white.opacity(0.18), lineWidth: max(0.8, size.width * 0.008))
          }
          .shadow(color: .black.opacity(0.10), radius: max(2, size.width * 0.025), y: max(2, size.height * 0.035))

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

private struct MIRAStudioTornPaperShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.035))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.012, y: rect.maxY - rect.height * 0.05))
    for step in stride(from: CGFloat(1), through: CGFloat(0), by: CGFloat(-0.045)) {
      let x = rect.minX + rect.width * step
      let wobble = CGFloat(Int(step * 1_000) % 3 - 1) * rect.height * 0.026
      path.addLine(to: CGPoint(x: x, y: rect.maxY + wobble))
    }
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.012, y: rect.minY + rect.height * 0.08))
    path.closeSubpath()
    return path
  }
}

private struct MIRAStudioOrganicShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.midY),
      control1: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY),
      control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.24)
    )
    path.addCurve(
      to: CGPoint(x: rect.midX, y: rect.maxY),
      control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.84),
      control2: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.maxY)
    )
    path.addCurve(
      to: CGPoint(x: rect.minX, y: rect.midY),
      control1: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.maxY),
      control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.72)
    )
    path.addCurve(
      to: CGPoint(x: rect.midX, y: rect.minY),
      control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16),
      control2: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY)
    )
    path.closeSubpath()
    return path
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
