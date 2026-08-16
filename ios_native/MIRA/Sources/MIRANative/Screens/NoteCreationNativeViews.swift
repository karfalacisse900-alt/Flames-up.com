import PhotosUI
import SwiftUI

public struct NoteCreationFlowView: View {
  public let api: MIRAAPIClient
  private let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var currentUser: MIRAUser?
  @State private var step: CreationStep = .entry
  @State private var selectedFormat: NoteCanvasFormat = .portrait
  @State private var document: NoteDocument?
  @State private var importedArtworkItem: PhotosPickerItem?
  @State private var editorPhotoItem: PhotosPickerItem?
  @State private var isUploading = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient, onClose: (() -> Void)? = nil) {
    self.api = api
    self.onClose = onClose
  }

  public var body: some View {
    NavigationStack {
      Group {
        switch step {
        case .entry:
          entryView
        case .format:
          formatView
        case .templates:
          templatePicker
        case .editor:
          if let document {
            NoteCanvasEditor(
              api: api,
              document: bindingDocument(document),
              isUploading: isUploading,
              errorMessage: errorMessage,
              photoPickerItem: $editorPhotoItem,
              onBack: { step = .entry },
              onDone: { step = .publish }
            )
          }
        case .publish:
          if let document {
            NotePublishView(
              api: api,
              document: bindingDocument(document),
              isUploading: isUploading,
              onBack: { step = .editor },
              onPublished: { close() }
            )
          }
        }
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
      .task {
        if currentUser == nil {
          let user: MIRAUser? = try? await api.get("/auth/me")
          currentUser = user
        }
        restoreDraftIfAvailable()
      }
      .onChange(of: importedArtworkItem) { _, item in
        Task { await importFinishedArtwork(item) }
      }
      .onChange(of: editorPhotoItem) { _, item in
        Task { await addEditorPhoto(item) }
      }
    }
  }

  private var entryView: some View {
    VStack(alignment: .leading, spacing: 0) {
      creationHeader(title: "Create a Note")

      VStack(alignment: .leading, spacing: 18) {
        Text("Choose how this visual page starts.")
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.top, MIRATheme.Space.md)

        VStack(spacing: 12) {
          NoteCreationPathButton(title: "Start Blank", subtitle: "Build your own visual page", systemImage: "square.dashed") {
            step = .format
          }

          NoteCreationPathButton(title: "Use a Template", subtitle: "Start with an editable design", systemImage: "rectangle.on.rectangle.angled") {
            step = .templates
          }

          PhotosPicker(selection: $importedArtworkItem, matching: .images) {
            NoteCreationPathButtonLabel(title: "Upload Finished Design", subtitle: "Post a flyer, poster or artwork you already made", systemImage: "photo.badge.plus")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Upload finished design")
        }
        .padding(.horizontal, MIRATheme.Space.md)

        if isUploading {
          HStack(spacing: 10) {
            ProgressView()
            Text("Preparing artwork...")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
          .padding(.horizontal, MIRATheme.Space.md)
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, MIRATheme.Space.md)
        }

        Spacer()
      }
    }
  }

  private var formatView: some View {
    VStack(alignment: .leading, spacing: 0) {
      creationHeader(title: "Canvas Size", showsBack: true)

      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(NoteCanvasFormat.allCases) { format in
            Button {
              selectedFormat = format
              document = NoteTemplateLibrary.blank(format: format, authorID: currentUser?.id ?? "")
              persistDraft()
              step = .editor
            } label: {
              VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .fill(format == .posterStory ? Color.miraHex("#171A17") : Color.miraHex("#F4EFE4"))
                  .aspectRatio(format.aspectRatio, contentMode: .fit)
                  .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                      .stroke(MIRATheme.Color.hairline, lineWidth: 1)
                  )
                Text(format.title)
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                Text(format.subtitle)
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(MIRATheme.Color.textMuted)
              }
              .padding(12)
              .background(MIRATheme.Color.surfaceSoft)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(MIRATheme.Space.md)
      }
    }
  }

  private var templatePicker: some View {
    VStack(alignment: .leading, spacing: 0) {
      creationHeader(title: "Templates", showsBack: true)

      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
          ForEach(NoteTemplateLibrary.templates) { template in
            Button {
              var next = template.document
              next.id = UUID().uuidString
              next.authorId = currentUser?.id ?? ""
              document = next
              persistDraft()
              step = .editor
            } label: {
              VStack(alignment: .leading, spacing: 9) {
                NoteCanvasRenderer(document: template.document, mode: .wall)
                  .shadow(color: .black.opacity(0.11), radius: 10, x: 0, y: 5)
                Text(template.title)
                  .font(.system(size: 15, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                  .lineLimit(1)
                Text(template.subtitle)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(MIRATheme.Color.textMuted)
                  .lineLimit(1)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(MIRATheme.Space.md)
      }
    }
  }

  private func creationHeader(title: String, showsBack: Bool = false) -> some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Button {
        if showsBack {
          step = .entry
        } else {
          close()
        }
      } label: {
        Image(systemName: showsBack ? "chevron.left" : "xmark")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(showsBack ? "Back" : "Close")

      Text(title)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, MIRATheme.Space.sm)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private func bindingDocument(_ fallback: NoteDocument) -> Binding<NoteDocument> {
    Binding(
      get: { document ?? fallback },
      set: {
        document = $0
        persistDraft()
      }
    )
  }

  @MainActor
  private func importFinishedArtwork(_ item: PhotosPickerItem?) async {
    guard let item else { return }
    isUploading = true
    errorMessage = nil
    defer {
      isUploading = false
      importedArtworkItem = nil
    }
    do {
      let url = try await upload(item)
      document = NoteTemplateLibrary.importedArtwork(mediaURL: url, authorID: currentUser?.id ?? "", format: selectedFormat)
      persistDraft()
      step = .publish
    } catch {
      errorMessage = "The artwork could not be imported."
    }
  }

  @MainActor
  private func addEditorPhoto(_ item: PhotosPickerItem?) async {
    guard let item, var next = document else { return }
    isUploading = true
    errorMessage = nil
    defer {
      isUploading = false
      editorPhotoItem = nil
    }
    do {
      let url = try await upload(item)
      if let index = next.canvas.elements.firstIndex(where: { $0.kind == .photo && ($0.photo?.url.isEmpty ?? true) }) {
        next.canvas.elements[index].photo = PhotoElement(url: url, originalURL: url, presentation: next.canvas.elements[index].photo?.presentation ?? .borderless)
        next.canvas.elements[index].accessibilityLabel = "Photo"
      } else {
        let size = min(next.canvas.designWidth * 0.72, next.canvas.designHeight * 0.48)
        next.canvas.elements.append(
          CanvasElement(
            kind: .photo,
            transform: ElementTransform(
              x: (next.canvas.designWidth - size) / 2,
              y: (next.canvas.designHeight - size) / 2,
              width: size,
              height: size,
              zIndex: next.nextZIndex
            ),
            photo: PhotoElement(url: url, originalURL: url, presentation: .printed),
            accessibilityLabel: "Photo"
          )
        )
      }
      next.thumbnailReference = next.thumbnailReference ?? url
      document = next
      persistDraft()
    } catch {
      errorMessage = "The photo could not be added."
    }
  }

  private func upload(_ item: PhotosPickerItem) async throws -> String {
    guard let data = try await item.loadTransferable(type: Data.self) else { throw MIRAAPIError.emptyResponse }
    let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
    let picked = MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType)
    return try await MIRAMediaUploadService(api: api).upload(picked)
  }

  private func persistDraft() {
    guard let document else { return }
    Task.detached(priority: .utility) {
      guard let data = try? JSONEncoder().encode(document) else { return }
      UserDefaults.standard.set(data, forKey: "mira.noteDocumentDraft.v1")
    }
  }

  private func restoreDraftIfAvailable() {
    guard document == nil, let data = UserDefaults.standard.data(forKey: "mira.noteDocumentDraft.v1") else { return }
    document = try? JSONDecoder().decode(NoteDocument.self, from: data)
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }
}

private enum CreationStep {
  case entry
  case format
  case templates
  case editor
  case publish
}

private struct NoteCanvasEditor: View {
  let api: MIRAAPIClient
  @Binding var document: NoteDocument
  let isUploading: Bool
  let errorMessage: String?
  @Binding var photoPickerItem: PhotosPickerItem?
  let onBack: () -> Void
  let onDone: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedElementID: String?
  @State private var undoStack: [NoteDocument] = []
  @State private var redoStack: [NoteDocument] = []
  @State private var dragOrigins: [String: ElementTransform] = [:]
  @State private var zoom: CGFloat = 1

  var body: some View {
    VStack(spacing: 0) {
      editorTopBar
      canvasWorkSurface
      editorBottomBar
    }
    .background(Color.miraHex("#EDEAE2").ignoresSafeArea())
  }

  private var editorTopBar: some View {
    HStack(spacing: 10) {
      Button(action: onBack) {
        Image(systemName: "xmark")
          .frame(width: 42, height: 42)
      }
      .accessibilityLabel("Close editor")

      Spacer()

      Button(action: undo) {
        Image(systemName: "arrow.uturn.backward")
          .frame(width: 38, height: 42)
      }
      .disabled(undoStack.isEmpty)
      .accessibilityLabel("Undo")

      Button(action: redo) {
        Image(systemName: "arrow.uturn.forward")
          .frame(width: 38, height: 42)
      }
      .disabled(redoStack.isEmpty)
      .accessibilityLabel("Redo")

      Button(action: onDone) {
        Text("Done")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 72, height: 40)
          .background(MIRATheme.Color.forest)
          .clipShape(Capsule())
      }
    }
    .font(.system(size: 17, weight: .semibold))
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 8)
    .background(MIRATheme.Color.surface)
  }

  private var canvasWorkSurface: some View {
    GeometryReader { proxy in
      let availableWidth = max(1, proxy.size.width - 36)
      let availableHeight = max(1, proxy.size.height - 36)
      let canvasAspect = document.canvasAspectRatio
      let fittedWidth = canvasAspect >= availableWidth / availableHeight ? availableWidth : availableHeight * canvasAspect
      let canvasWidth = min(availableWidth, fittedWidth) * zoom

      ScrollView([.horizontal, .vertical], showsIndicators: false) {
        ZStack(alignment: .topLeading) {
          NoteCanvasRenderer(document: document, mode: .editor(selectedElementID: selectedElementID))
            .frame(width: canvasWidth)
            .shadow(color: .black.opacity(0.17), radius: 18, x: 0, y: 10)
            .overlay(editorHitTargets(canvasWidth: canvasWidth))
        }
        .padding(18)
        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
      }
      .background(Color.miraHex("#EDEAE2"))
      .gesture(
        MagnificationGesture()
          .onChanged { value in
            zoom = min(max(0.72, value), 2.6)
          }
      )
    }
  }

  private func editorHitTargets(canvasWidth: CGFloat) -> some View {
    let scale = canvasWidth / max(1, document.canvas.designWidth)
    return ZStack(alignment: .topLeading) {
      ForEach(document.canvas.elements.filter { !$0.isHidden }) { element in
        Rectangle()
          .fill(Color.clear)
          .contentShape(Rectangle())
          .frame(width: element.transform.width * scale, height: element.transform.height * scale)
          .rotationEffect(.degrees(element.transform.rotation))
          .position(
            x: (element.transform.x + element.transform.width / 2) * scale,
            y: (element.transform.y + element.transform.height / 2) * scale
          )
          .onTapGesture {
            selectedElementID = element.id
          }
          .gesture(
            DragGesture()
              .onChanged { value in
                guard selectedElementID == element.id else { return }
                move(elementID: element.id, translation: value.translation, scale: scale)
              }
              .onEnded { _ in
                dragOrigins[element.id] = nil
                persistAutosave()
                if !reduceMotion {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
              }
          )
      }
    }
  }

  private var editorBottomBar: some View {
    VStack(spacing: 10) {
      if let selectedElement {
        selectedControls(for: selectedElement)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          PhotosPicker(selection: $photoPickerItem, matching: .images) {
            NoteToolButtonLabel(title: "Photo", systemImage: "photo")
          }
          .buttonStyle(.plain)

          NoteToolButton(title: "Text", systemImage: "textformat") {
            mutateDocument {
              $0.canvas.elements.append(CanvasElement(kind: .text, transform: centeredTransform(in: $0.canvas, width: 650, height: 180, z: $0.nextZIndex), text: TextElement(text: "New text", role: .title, size: 64, weight: .semibold), accessibilityLabel: "New text"))
            }
          }

          NoteToolButton(title: "Paper", systemImage: "doc") {
            mutateDocument {
              $0.canvas.elements.append(CanvasElement(kind: .paper, transform: centeredTransform(in: $0.canvas, width: 620, height: 300, z: $0.nextZIndex), material: .creamPaper))
            }
          }

          NoteToolButton(title: "Decorate", systemImage: "sparkles") {
            mutateDocument {
              $0.canvas.elements.append(CanvasElement(kind: .tape, transform: centeredTransform(in: $0.canvas, width: 260, height: 62, z: $0.nextZIndex), accessibilityLabel: "Tape"))
            }
          }

          NoteToolButton(title: "Draw", systemImage: "pencil.and.scribble") {
            mutateDocument {
              $0.canvas.elements.append(CanvasElement(kind: .drawing, transform: centeredTransform(in: $0.canvas, width: 420, height: 160, z: $0.nextZIndex), accessibilityLabel: "Drawing"))
            }
          }

          NoteToolButton(title: "Background", systemImage: "paintpalette") {
            cycleBackground()
          }
        }
        .padding(.horizontal, MIRATheme.Space.md)
      }

      if isUploading {
        HStack(spacing: 8) {
          ProgressView()
          Text("Uploading media...")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      } else if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.red)
      }
    }
    .padding(.vertical, 10)
    .background(MIRATheme.Color.surface)
  }

  private func selectedControls(for element: CanvasElement) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        NoteToolButton(title: "Duplicate", systemImage: "plus.square.on.square") { duplicate(element) }
        NoteToolButton(title: "Forward", systemImage: "square.2.layers.3d.top.filled") { reorder(elementID: element.id, delta: 1) }
        NoteToolButton(title: "Back", systemImage: "square.2.layers.3d.bottom.filled") { reorder(elementID: element.id, delta: -1) }
        NoteToolButton(title: "Opacity", systemImage: "circle.lefthalf.filled") { cycleOpacity(elementID: element.id) }
        NoteToolButton(title: "Delete", systemImage: "trash") { delete(elementID: element.id) }
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
  }

  private var selectedElement: CanvasElement? {
    guard let selectedElementID else { return nil }
    return document.canvas.elements.first(where: { $0.id == selectedElementID })
  }

  private func mutateDocument(_ update: (inout NoteDocument) -> Void) {
    undoStack.append(document)
    redoStack.removeAll()
    update(&document)
    persistAutosave()
  }

  private func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(document)
    document = previous
  }

  private func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(document)
    document = next
  }

  private func move(elementID: String, translation: CGSize, scale: CGFloat) {
    guard let index = document.canvas.elements.firstIndex(where: { $0.id == elementID }), scale > 0 else { return }
    if dragOrigins[elementID] == nil {
      undoStack.append(document)
      redoStack.removeAll()
      dragOrigins[elementID] = document.canvas.elements[index].transform
    }
    guard let origin = dragOrigins[elementID] else { return }
    document.canvas.elements[index].transform.x = origin.x + translation.width / scale
    document.canvas.elements[index].transform.y = origin.y + translation.height / scale
  }

  private func duplicate(_ element: CanvasElement) {
    mutateDocument {
      var copy = element
      copy.id = UUID().uuidString
      copy.transform.x += 42
      copy.transform.y += 42
      copy.transform.zIndex = $0.nextZIndex
      $0.canvas.elements.append(copy)
      selectedElementID = copy.id
    }
  }

  private func delete(elementID: String) {
    mutateDocument {
      $0.canvas.elements.removeAll { $0.id == elementID }
      selectedElementID = nil
    }
  }

  private func reorder(elementID: String, delta: Int) {
    mutateDocument {
      guard let index = $0.canvas.elements.firstIndex(where: { $0.id == elementID }) else { return }
      $0.canvas.elements[index].transform.zIndex += delta
    }
  }

  private func cycleOpacity(elementID: String) {
    mutateDocument {
      guard let index = $0.canvas.elements.firstIndex(where: { $0.id == elementID }) else { return }
      let current = $0.canvas.elements[index].transform.opacity
      $0.canvas.elements[index].transform.opacity = current <= 0.55 ? 1 : current - 0.25
    }
  }

  private func cycleBackground() {
    mutateDocument {
      switch $0.canvas.background {
      case .solid, .gradient:
        $0.canvas.background = .material(.whiteCottonPaper)
      case .material(.whiteCottonPaper):
        $0.canvas.background = .material(.blackLeather)
      case .material(.blackLeather):
        $0.canvas.background = .gradient(["#F8E16C", "#EF6B61", "#25476A"])
      default:
        $0.canvas.background = .solid("#F8F5EE")
      }
    }
  }

  private func centeredTransform(in canvas: NoteCanvas, width: CGFloat, height: CGFloat, z: Int) -> ElementTransform {
    ElementTransform(x: (canvas.designWidth - width) / 2, y: (canvas.designHeight - height) / 2, width: width, height: height, zIndex: z)
  }

  private func persistAutosave() {
    let snapshot = document
    Task.detached(priority: .utility) {
      guard let data = try? JSONEncoder().encode(snapshot) else { return }
      UserDefaults.standard.set(data, forKey: "mira.noteDocumentDraft.v1")
    }
  }
}

private struct NotePublishView: View {
  let api: MIRAAPIClient
  @Binding var document: NoteDocument
  let isUploading: Bool
  let onBack: () -> Void
  let onPublished: () -> Void
  @State private var caption = ""
  @State private var altText = ""
  @State private var visibility: NoteVisibility = .everyone
  @State private var isPublishing = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button(action: onBack) {
          Image(systemName: "chevron.left")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 44, height: 44)
        }
        Spacer()
        Text("Publish")
          .font(.system(size: 20, weight: .semibold))
        Spacer()
        Button {
          Task { await publish() }
        } label: {
          if isPublishing {
            ProgressView().tint(.white)
          } else {
            Text("Post")
              .font(.system(size: 15, weight: .semibold))
          }
        }
        .foregroundStyle(.white)
        .frame(width: 74, height: 40)
        .background(canPublish ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.5))
        .clipShape(Capsule())
        .disabled(!canPublish)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, 8)
      .background(MIRATheme.Color.surface)

      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          NoteCanvasRenderer(document: document, mode: .detail)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.13), radius: 16, x: 0, y: 8)

          VStack(alignment: .leading, spacing: 12) {
            TextField("Optional caption", text: $caption, axis: .vertical)
              .lineLimit(2...5)
              .textFieldStyle(.plain)
              .font(.system(size: 16, weight: .medium))
              .padding(14)
              .background(MIRATheme.Color.surfaceSoft)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            TextField("Alt text for accessibility", text: $altText, axis: .vertical)
              .lineLimit(2...4)
              .textFieldStyle(.plain)
              .font(.system(size: 15, weight: .medium))
              .padding(14)
              .background(MIRATheme.Color.surfaceSoft)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }

          visibilityPicker
          detailBlockControls

          if isUploading || isPublishing {
            HStack(spacing: 10) {
              ProgressView()
              Text(isPublishing ? "Publishing note..." : "Uploading media...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textSecondary)
            }
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.red)
          }
        }
        .padding(MIRATheme.Space.md)
      }
    }
    .background(MIRATheme.Color.appBackground)
    .onAppear {
      caption = document.caption ?? ""
      altText = document.altText ?? ""
      visibility = document.visibility
    }
  }

  private var visibilityPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Visibility")
        .font(.system(size: 15, weight: .semibold))
      HStack(spacing: 9) {
        ForEach([NoteVisibility.everyone, .friends, .private], id: \.self) { option in
          Button {
            visibility = option
          } label: {
            Text(option.label)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(visibility == option ? .white : MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity)
              .frame(height: 38)
              .background(visibility == option ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var detailBlockControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Add details")
        .font(.system(size: 15, weight: .semibold))

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        DetailBlockButton(title: "Event", systemImage: "calendar") { addEventBlock() }
        DetailBlockButton(title: "Recipe", systemImage: "fork.knife") { addRecipeBlock() }
        DetailBlockButton(title: "Book Review", systemImage: "book") { addReviewBlock() }
        DetailBlockButton(title: "Link", systemImage: "link") { addLinkBlock() }
      }

      ForEach(document.detailBlocks) { block in
        NoteDetailBlockSummary(block: block)
      }
    }
  }

  private var canPublish: Bool {
    !isPublishing && !isUploading && !document.canvas.elements.isEmpty
  }

  private func publish() async {
    isPublishing = true
    errorMessage = nil
    defer { isPublishing = false }
    do {
      document.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
      document.altText = altText.trimmingCharacters(in: .whitespacesAndNewlines)
      document.visibility = visibility
      let primaryMedia = document.thumbnailReference ?? document.firstPhotoURL
      let _: MIRANote = try await api.post(
        "/notes",
        body: CreateNoteBody(
          body: document.caption ?? "",
          mediaUrl: primaryMedia,
          color: nil,
          noteType: document.contentKind?.rawValue,
          document: document,
          artworkMode: document.artworkMode,
          contentKind: document.contentKind,
          detailBlocks: document.detailBlocks,
          visibility: document.visibility,
          thumbnailReference: primaryMedia,
          altText: document.altText
        )
      )
      UserDefaults.standard.removeObject(forKey: "mira.noteDocumentDraft.v1")
      onPublished()
    } catch {
      errorMessage = "The note could not be published."
    }
  }

  private func addEventBlock() {
    document.contentKind = .event
    document.detailBlocks.append(.event(NoteEventDetailBlock(title: "Event title", date: "Date", startTime: nil, endTime: nil, venue: nil, address: nil, ticketUrl: nil, organizer: nil, ageRestriction: nil)))
  }

  private func addRecipeBlock() {
    document.contentKind = .recipe
    document.detailBlocks.append(.recipe(NoteRecipeDetailBlock(title: "Recipe title", prepTime: nil, cookTime: nil, servings: nil, ingredients: ["Ingredient"], steps: ["Step"], sourceUrl: nil)))
  }

  private func addReviewBlock() {
    document.contentKind = .review
    document.detailBlocks.append(.bookReview(NoteBookReviewDetailBlock(title: "Book title", author: nil, rating: nil, review: "Review text", favoriteQuote: nil, link: nil)))
  }

  private func addLinkBlock() {
    document.contentKind = document.contentKind ?? .link
    document.detailBlocks.append(.link(NoteLinkDetailBlock(title: "Link title", description: nil, url: "https://")))
  }
}

private struct NoteCreationPathButton: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      NoteCreationPathButtonLabel(title: title, subtitle: subtitle, systemImage: systemImage)
    }
    .buttonStyle(.plain)
  }
}

private struct NoteCreationPathButtonLabel: View {
  let title: String
  let subtitle: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(subtitle)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .padding(14)
    .background(MIRATheme.Color.surfaceSoft)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct NoteToolButton: View {
  let title: String
  let systemImage: String
  var action: (() -> Void)?

  var body: some View {
    Button {
      action?()
    } label: {
      NoteToolButtonLabel(title: title, systemImage: systemImage)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}

private struct NoteToolButtonLabel: View {
  let title: String
  let systemImage: String

  var body: some View {
    VStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 42, height: 34)
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .frame(width: 76, height: 58)
  }
}

private struct DetailBlockButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

private struct NoteDetailBlockSummary: View {
  let block: NoteDetailBlock

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(MIRATheme.Color.forest)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
        Text(subtitle)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(2)
      }
      Spacer()
    }
    .padding(12)
    .background(MIRATheme.Color.surfaceSoft.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var icon: String {
    switch block {
    case .event: return "calendar"
    case .recipe: return "fork.knife"
    case .bookReview: return "book"
    case .location: return "mappin"
    case .link: return "link"
    case .credits: return "person.2"
    case .text: return "text.alignleft"
    }
  }

  private var title: String {
    switch block {
    case .event(let block): return block.title
    case .recipe(let block): return block.title
    case .bookReview(let block): return block.title
    case .location(let block): return block.placeName
    case .link(let block): return block.title
    case .credits: return "Credits"
    case .text(let block): return block.heading
    }
  }

  private var subtitle: String {
    switch block {
    case .event(let block): return [block.date, block.venue].compactMap { $0 }.joined(separator: " · ")
    case .recipe(let block): return "\(block.ingredients.count) ingredients · \(block.steps.count) steps"
    case .bookReview(let block): return block.author ?? "Book review"
    case .location(let block): return block.city ?? "Location"
    case .link(let block): return block.url
    case .credits(let block): return [block.photographer, block.designer, block.artist].compactMap { $0 }.joined(separator: " · ")
    case .text(let block): return block.body
    }
  }
}

private extension NoteVisibility {
  var label: String {
    switch self {
    case .everyone: return "Everyone"
    case .friends: return "Friends"
    case .private: return "Private"
    case .draft: return "Draft"
    }
  }
}

private extension NoteDocument {
  var firstPhotoURL: String? {
    canvas.elements.compactMap { element -> String? in
      guard element.kind == .photo else { return nil }
      let url = element.photo?.url.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return url.isEmpty ? nil : url
    }.first
  }

  var nextZIndex: Int {
    (canvas.elements.map { $0.transform.zIndex }.max() ?? 0) + 1
  }
}
