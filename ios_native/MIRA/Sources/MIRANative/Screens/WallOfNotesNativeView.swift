import SwiftUI

@MainActor
final class MIRAWallNotesModel: ObservableObject {
  @Published private(set) var notes: [MIRAWallNote] = []
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?

  private let api: MIRAAPIClient
  private var spatialIndex = MIRAWallSpatialIndex()
  private var inFlightSignature: String?
  private var lastLoadedSignature: String?

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func visibleNotes(in bounds: CGRect) -> [MIRAWallNote] {
    spatialIndex.notes(in: bounds)
  }

  func note(at point: CGPoint) -> MIRAWallNote? {
    spatialIndex.note(at: point)
  }

  func load(bounds: CGRect, zoom: CGFloat, filter: String, query: String, force: Bool = false) async {
    let expanded = bounds.insetBy(dx: -max(420, bounds.width * 0.35), dy: -max(600, bounds.height * 0.35))
    let signature = [
      String(Int(expanded.minX / 320)), String(Int(expanded.maxX / 320)),
      String(Int(expanded.minY / 320)), String(Int(expanded.maxY / 320)),
      String(format: "%.1f", zoom), filter, query.trimmingCharacters(in: .whitespacesAndNewlines),
    ].joined(separator: ":")
    guard force || (signature != lastLoadedSignature && signature != inFlightSignature) else { return }
    inFlightSignature = signature
    if notes.isEmpty { isLoading = true }
    errorMessage = nil
    defer {
      isLoading = false
      if inFlightSignature == signature { inFlightSignature = nil }
    }

    var components = URLComponents()
    components.path = "/wall/notes"
    components.queryItems = [
      URLQueryItem(name: "wall_id", value: "global"),
      URLQueryItem(name: "min_x", value: String(Double(expanded.minX))),
      URLQueryItem(name: "max_x", value: String(Double(expanded.maxX))),
      URLQueryItem(name: "min_y", value: String(Double(expanded.minY))),
      URLQueryItem(name: "max_y", value: String(Double(expanded.maxY))),
      URLQueryItem(name: "zoom", value: String(Double(zoom))),
      URLQueryItem(name: "filter", value: filter),
      URLQueryItem(name: "query", value: query),
      URLQueryItem(name: "limit", value: zoom < 0.45 ? "600" : "320"),
    ]
    do {
      let response: MIRAWallNotesResponse = try await api.get(components.string ?? "/wall/notes")
      merge(response.notes, around: bounds)
      lastLoadedSignature = signature
    } catch is CancellationError {
      return
    } catch {
      if notes.isEmpty { errorMessage = error.localizedDescription }
    }
  }

  func create(_ body: MIRACreateWallNoteBody) async throws -> MIRAWallNote {
    let response: MIRAWallNoteResponse = try await api.post("/wall/notes", body: body)
    merge([response.note], around: CGRect(x: response.note.worldX - 900, y: response.note.worldY - 900, width: 1800, height: 1800))
    return response.note
  }

  func setReaction(note: MIRAWallNote, reacted: Bool) async throws -> MIRAWallNote {
    update(note.updating(reacted: reacted, reactionCount: max(0, note.reactionCount + (reacted ? 1 : -1))))
    do {
      let response: MIRAWallToggleResponse = try await api.post("/wall/notes/\(note.id)/reaction", body: MIRAWallReactionBody(reacted: reacted))
      let reconciled = note.updating(reacted: response.reacted ?? reacted, reactionCount: response.reactionCount ?? note.reactionCount)
      update(reconciled)
      return reconciled
    } catch {
      update(note)
      throw error
    }
  }

  func setSaved(note: MIRAWallNote, saved: Bool) async throws -> MIRAWallNote {
    update(note.updating(saved: saved, saveCount: max(0, note.saveCount + (saved ? 1 : -1))))
    do {
      let response: MIRAWallToggleResponse = try await api.post("/wall/notes/\(note.id)/save", body: MIRAWallSaveBody(saved: saved))
      let reconciled = note.updating(saved: response.saved ?? saved, saveCount: response.saveCount ?? note.saveCount)
      update(reconciled)
      return reconciled
    } catch {
      update(note)
      throw error
    }
  }

  func addReply(note: MIRAWallNote, body: String, identity: String) async throws -> MIRAWallReply {
    let response: MIRAWallReplyResponse = try await api.post(
      "/wall/notes/\(note.id)/replies",
      body: MIRAWallReplyBody(body: body, publishingIdentity: identity)
    )
    update(note.updating(replyCount: response.replyCount ?? note.replyCount + 1))
    return response.reply
  }

  func replies(for note: MIRAWallNote) async throws -> [MIRAWallReply] {
    let response: MIRAWallRepliesResponse = try await api.get("/wall/notes/\(note.id)/replies")
    return response.replies
  }

  private func merge(_ incoming: [MIRAWallNote], around bounds: CGRect) {
    var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    incoming.forEach { byID[$0.id] = $0 }
    let retention = bounds.insetBy(dx: -max(5000, bounds.width * 2.5), dy: -max(5000, bounds.height * 2.5))
    let retained = byID.values.filter { note in
      retention.intersects(CGRect(x: note.worldX, y: note.worldY, width: note.width, height: note.height))
    }
    notes = Array(retained.prefix(3000))
    spatialIndex.rebuild(with: notes)
  }

  private func update(_ note: MIRAWallNote) {
    if let index = notes.firstIndex(where: { $0.id == note.id }) {
      notes[index] = note
    } else {
      notes.append(note)
    }
    spatialIndex.rebuild(with: notes)
  }
}

public struct WallOfNotesNativeView: View {
  private let api: MIRAAPIClient
  @StateObject private var model: MIRAWallNotesModel
  @State private var camera = MIRAWallCamera()
  @State private var panStart: MIRAWallCamera?
  @State private var magnifyStart: MIRAWallCamera?
  @State private var selectedNote: MIRAWallNote?
  @State private var isCreating = false
  @State private var isSearching = false
  @State private var query = ""
  @State private var selectedFilter = "all"
  @State private var showFilters = false
  @State private var placementNoteID: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(api: MIRAAPIClient) {
    self.api = api
    _model = StateObject(wrappedValue: MIRAWallNotesModel(api: api))
  }

  public var body: some View {
    GeometryReader { proxy in
      let viewport = proxy.size
      let bounds = camera.worldBounds(viewport: viewport)
      ZStack {
        MIRAWallBackground(camera: camera, viewport: viewport)
          .ignoresSafeArea()

        wallNotes(bounds: bounds, viewport: viewport)

        chrome(viewport: viewport)

        if model.notes.isEmpty, !model.isLoading, model.errorMessage == nil {
          emptyState
        }

        if let message = model.errorMessage, model.notes.isEmpty {
          errorState(message: message, bounds: bounds)
        }
      }
      .contentShape(Rectangle())
      .clipped()
      .gesture(panGesture(viewport: viewport).simultaneously(with: magnifyGesture(viewport: viewport)))
      .simultaneousGesture(SpatialTapGesture().onEnded { value in
        guard panStart == nil, magnifyStart == nil else { return }
        let world = camera.worldPoint(forScreen: value.location, viewport: viewport)
        if let note = model.note(at: world) {
          withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
            selectedNote = note
          }
        }
      })
      .simultaneousGesture(
        SpatialTapGesture(count: 2).onEnded { value in
          withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
            camera = camera.zoomed(to: camera.scale < 1.25 ? min(1.55, camera.scale * 1.8) : 0.62, around: value.location, viewport: viewport)
          }
        }
      )
      .task(id: loadKey(bounds: bounds)) {
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        await model.load(bounds: bounds, zoom: camera.scale, filter: selectedFilter, query: query)
      }
      .sheet(isPresented: $isCreating) {
        MIRACreateWallNoteView(camera: camera, api: api) { body in
          let note = try await model.create(body)
          placementNoteID = note.id
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            placementNoteID = nil
          }
          return note
        }
        .presentationDetents([.large])
        .presentationCornerRadius(30)
      }
      .miraFadeScaleOverlay(isPresented: Binding(
        get: { selectedNote != nil },
        set: { if !$0 { selectedNote = nil } }
      )) { dismiss in
        if let note = selectedNote {
          MIRAWallNoteDetailView(note: note, api: api, model: model) { updated in
            selectedNote = updated
          } onClose: {
            dismiss()
          }
        }
      }
      .miraActionModal(isPresented: $showFilters) { dismiss in
        MIRAActionModalCard {
          ScrollView(showsIndicators: false) {
            VStack(spacing: 7) {
              ForEach(MIRAWallFilter.allCases) { filter in
                MIRAActionModalButton(
                  title: filter.title,
                  systemImage: filter.icon,
                  staggerIndex: filter.staggerIndex
                ) {
                  selectedFilter = filter.rawValue
                  dismiss()
                }
              }
            }
          }
          .frame(maxHeight: 470)
        }
      }
    }
    .background(MIRATheme.Color.launchBackground)
  }

  @ViewBuilder
  private func wallNotes(bounds: CGRect, viewport: CGSize) -> some View {
    let preload = max(180, 240 / max(camera.scale, 0.2))
    let visible = model.visibleNotes(in: bounds.insetBy(dx: -preload, dy: -preload))
    ZStack {
      ForEach(visible) { note in
        let center = camera.screenPoint(
          forWorld: CGPoint(x: note.worldX + note.width * 0.5, y: note.worldY + note.height * 0.5),
          viewport: viewport
        )
        MIRAWallNoteSurface(note: note, zoom: camera.scale)
          .frame(width: note.width * camera.scale, height: note.height * camera.scale)
          .position(center)
          .rotationEffect(.degrees(note.rotation))
          .scaleEffect(placementNoteID == note.id ? 1 : 1)
          .transition(.scale(scale: reduceMotion ? 1 : 1.18).combined(with: .opacity))
          .allowsHitTesting(false)
          .zIndex(Double(note.zIndex))
      }
    }
    .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.58, dampingFraction: 0.78), value: placementNoteID)
  }

  private func chrome(viewport: CGSize) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 7) {
          Text("Wall of Notes")
            .font(.system(size: 25, weight: .bold, design: .serif))
            .foregroundStyle(MIRATheme.Color.textPrimary)

          Label("Global", systemImage: "globe.americas.fill")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(MIRATheme.Color.surface.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(MIRATheme.Color.hairline, lineWidth: 1))
        }

        Spacer(minLength: 8)

        if isSearching {
          TextField("Search notes", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(MIRATheme.Color.surface.opacity(0.96), in: Capsule())
            .frame(maxWidth: 190)
            .submitLabel(.search)
        }

        wallIconButton(systemImage: isSearching ? "xmark" : "magnifyingglass") {
          withAnimation(CaptroMotion.smallMenuAnimation(reduceMotion: reduceMotion)) {
            isSearching.toggle()
            if !isSearching { query = "" }
          }
        }

        wallIconButton(systemImage: "line.3.horizontal.decrease") {
          showFilters = true
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      Spacer()

      HStack {
        wallIconButton(systemImage: "location.north.fill") {
          withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
            camera = MIRAWallCamera()
          }
        }

        Spacer()

        Button {
          isCreating = true
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(MIRATheme.Color.forest, in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel("Add note")

        Spacer()

        wallIconButton(systemImage: camera.scale < 0.6 ? "plus.magnifyingglass" : "minus.magnifyingglass") {
          withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
            camera.scale = camera.scale < 0.6 ? 0.92 : 0.38
          }
        }
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 16)
    }
    .allowsHitTesting(true)
  }

  private func wallIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.surface.opacity(0.94), in: Circle())
        .overlay(Circle().stroke(MIRATheme.Color.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
    }
    .buttonStyle(.miraPress)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "note.text")
        .font(.system(size: 30, weight: .light))
      Text(selectedFilter == "all" ? "This part of the wall is open." : "No matching notes here yet.")
        .font(.system(size: 16, weight: .semibold, design: .serif))
      Text("Move around or place the first note.")
        .font(.system(size: 13))
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .padding(24)
    .background(MIRATheme.Color.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .allowsHitTesting(false)
  }

  private func errorState(message: String, bounds: CGRect) -> some View {
    VStack(spacing: 12) {
      Text("Couldn’t load this part of the wall.")
        .font(.system(size: 16, weight: .semibold))
      Text(message)
        .font(.system(size: 13))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .multilineTextAlignment(.center)
      Button("Retry") {
        Task { await model.load(bounds: bounds, zoom: camera.scale, filter: selectedFilter, query: query, force: true) }
      }
      .buttonStyle(.borderedProminent)
      .tint(MIRATheme.Color.forest)
    }
    .padding(24)
    .background(MIRATheme.Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .padding(24)
  }

  private func panGesture(viewport: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .local)
      .onChanged { value in
        if panStart == nil { panStart = camera }
        guard let start = panStart else { return }
        camera.center = CGPoint(
          x: start.center.x - value.translation.width / max(start.scale, 0.2),
          y: start.center.y - value.translation.height / max(start.scale, 0.2)
        )
      }
      .onEnded { value in
        guard let start = panStart else { return }
        let projected = CGSize(
          width: value.predictedEndTranslation.width - value.translation.width,
          height: value.predictedEndTranslation.height - value.translation.height
        )
        panStart = nil
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.34)) {
          camera.center.x -= projected.width * 0.22 / max(start.scale, 0.2)
          camera.center.y -= projected.height * 0.22 / max(start.scale, 0.2)
        }
      }
  }

  private func magnifyGesture(viewport: CGSize) -> some Gesture {
    MagnifyGesture(minimumScaleDelta: 0.005)
      .onChanged { value in
        if magnifyStart == nil { magnifyStart = camera }
        guard let start = magnifyStart else { return }
        let anchor = CGPoint(x: value.startAnchor.x * viewport.width, y: value.startAnchor.y * viewport.height)
        camera = start.zoomed(to: start.scale * value.magnification, around: anchor, viewport: viewport)
      }
      .onEnded { _ in magnifyStart = nil }
  }

  private func loadKey(bounds: CGRect) -> String {
    [
      Int(bounds.midX / 260), Int(bounds.midY / 260), Int(camera.scale * 10),
    ].map(String.init).joined(separator: ":") + ":\(selectedFilter):\(query)"
  }
}

private enum MIRAWallFilter: String, CaseIterable, Identifiable {
  case all, ghost, author, recent, popular, saved, question, confession, food, advice, life, localRecommendation = "local_recommendation"

  var id: String { rawValue }
  var staggerIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
  var title: String {
    switch self {
    case .all: "All Notes"
    case .ghost: "Ghost"
    case .author: "Author"
    case .recent: "Recent"
    case .popular: "Popular"
    case .saved: "Saved"
    case .question: "Questions"
    case .confession: "Confessions"
    case .food: "Food"
    case .advice: "Advice"
    case .life: "Life"
    case .localRecommendation: "Local Recommendations"
    }
  }
  var icon: String {
    switch self {
    case .all: "note.text"
    case .ghost: "theatermask.and.paintbrush"
    case .author: "person.crop.circle"
    case .recent: "clock"
    case .popular: "sparkles"
    case .saved: "bookmark"
    case .question: "questionmark.bubble"
    case .confession: "lock"
    case .food: "fork.knife"
    case .advice: "lightbulb"
    case .life: "heart.text.square"
    case .localRecommendation: "mappin.and.ellipse"
    }
  }
}

private struct MIRAWallBackground: View {
  let camera: MIRAWallCamera
  let viewport: CGSize

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.925, green: 0.900, blue: 0.835)))
      let spacing = max(26, 72 * camera.scale)
      let offsetX = (-camera.center.x * camera.scale).truncatingRemainder(dividingBy: spacing)
      let offsetY = (-camera.center.y * camera.scale).truncatingRemainder(dividingBy: spacing)
      var dots = Path()
      var x = offsetX
      while x < size.width {
        var y = offsetY
        while y < size.height {
          dots.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
          y += spacing
        }
        x += spacing
      }
      context.fill(dots, with: .color(Color.black.opacity(0.045)))
    }
    .allowsHitTesting(false)
  }
}

struct MIRAWallNoteSurface: View {
  let note: MIRAWallNote
  let zoom: CGFloat

  var body: some View {
    let color = MIRAWallPaperColor.color(for: note.colorToken)
    ZStack {
      RoundedRectangle(cornerRadius: zoom > 1.1 ? 3 : 1, style: .continuous)
        .fill(color)

      if zoom >= 0.48 {
        Text(displayText)
          .font(noteFont)
          .foregroundStyle(Color(red: 0.10, green: 0.095, blue: 0.075))
          .multilineTextAlignment(note.styleToken == "editorial" ? .leading : .center)
          .lineLimit(zoom >= 0.95 ? 12 : 5)
          .minimumScaleFactor(0.55)
          .padding(max(8, 18 * zoom))
      }

      if zoom >= 0.72 {
        VStack {
          HStack {
            Image(systemName: note.isGhost ? "theatermask.and.paintbrush" : "person.crop.circle")
              .font(.system(size: max(8, 11 * zoom), weight: .semibold))
              .foregroundStyle(.black.opacity(0.45))
            Spacer()
          }
          Spacer()
        }
        .padding(max(5, 8 * zoom))
      }

      if note.styleToken == "torn_paper", zoom > 0.55 {
        VStack {
          Spacer()
          Rectangle().fill(.black.opacity(0.05)).frame(height: max(2, 4 * zoom))
        }
      }
    }
    .overlay(alignment: .top) {
      if zoom > 0.85 {
        Capsule()
          .fill(Color.white.opacity(0.44))
          .frame(width: max(20, 40 * zoom), height: max(4, 8 * zoom))
          .offset(y: -max(2, 4 * zoom))
      }
    }
    .shadow(color: .black.opacity(zoom < 0.45 ? 0.07 : 0.16), radius: zoom < 0.45 ? 1 : 5 * zoom, x: 0, y: max(1, 3 * zoom))
  }

  private var displayText: String {
    guard zoom < 0.78, note.body.count > 72 else { return note.body }
    return String(note.body.prefix(69)) + "…"
  }

  private var noteFont: Font {
    let size = max(7, min(25, 20 * zoom))
    switch note.styleToken {
    case "editorial": return .system(size: size, weight: .bold, design: .serif)
    case "question": return .system(size: size, weight: .semibold, design: .rounded)
    case "confession": return .system(size: size, weight: .medium, design: .serif)
    default: return .system(size: size, weight: .semibold, design: .rounded)
    }
  }
}

private enum MIRAWallPaperColor {
  static func color(for token: String) -> Color {
    switch token {
    case "cream": Color(red: 0.96, green: 0.93, blue: 0.84)
    case "rose": Color(red: 0.95, green: 0.67, blue: 0.71)
    case "sky": Color(red: 0.63, green: 0.83, blue: 0.84)
    case "mint": Color(red: 0.70, green: 0.84, blue: 0.65)
    case "peach": Color(red: 0.96, green: 0.73, blue: 0.55)
    case "paper": Color(red: 0.94, green: 0.93, blue: 0.87)
    default: Color(red: 0.94, green: 0.82, blue: 0.34)
    }
  }
}

private struct MIRACreateWallNoteView: View {
  let camera: MIRAWallCamera
  let api: MIRAAPIClient
  let onPublish: (MIRACreateWallNoteBody) async throws -> MIRAWallNote

  @Environment(\.dismiss) private var dismiss
  @State private var bodyText = ""
  @State private var identity = "ghost"
  @State private var colorToken = "butter"
  @State private var styleToken = "sticky_square"
  @State private var category = ""
  @State private var approximateLocation = ""
  @State private var isPublishing = false
  @State private var errorMessage: String?
  @FocusState private var isTextFocused: Bool

  private let colors = ["butter", "cream", "rose", "sky", "mint", "peach", "paper"]
  private let styles: [(String, String)] = [
    ("sticky_square", "Sticky"), ("vertical_card", "Vertical"), ("torn_paper", "Torn"),
    ("editorial", "Editorial"), ("question", "Question"), ("confession", "Confession"),
    ("recommendation", "Recommendation"),
  ]
  private let categories: [(String, String)] = [
    ("", "None"), ("question", "Question"), ("confession", "Confession"),
    ("food", "Food"), ("advice", "Advice"), ("life", "Life"),
    ("local_recommendation", "Local"),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          livePreview

          VStack(alignment: .leading, spacing: 9) {
            HStack {
              Text("YOUR NOTE")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MIRATheme.Color.textSecondary)
              Spacer()
              Text("\(bodyText.count)/300")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(bodyText.count >= 280 ? Color.orange : MIRATheme.Color.textMuted)
            }

            ZStack(alignment: .topLeading) {
              if bodyText.isEmpty {
                Text("Write your note…")
                  .foregroundStyle(MIRATheme.Color.textMuted)
                  .padding(.horizontal, 5)
                  .padding(.vertical, 8)
              }
              TextEditor(text: $bodyText)
                .focused($isTextFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 112)
                .onChange(of: bodyText) { _, value in
                  if value.count > 300 { bodyText = String(value.prefix(300)) }
                }
            }
            .padding(12)
            .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          }

          settingSection(title: "PAPER COLOR") {
            HStack(spacing: 13) {
              ForEach(colors, id: \.self) { token in
                Button {
                  colorToken = token
                } label: {
                  Circle()
                    .fill(MIRAWallPaperColor.color(for: token))
                    .frame(width: 31, height: 31)
                    .overlay(Circle().stroke(Color.black.opacity(colorToken == token ? 0.78 : 0.10), lineWidth: colorToken == token ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(token) note color")
              }
            }
          }

          settingSection(title: "NOTE STYLE") {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(styles, id: \.0) { item in
                  choiceChip(item.1, selected: styleToken == item.0) { styleToken = item.0 }
                }
              }
            }
          }

          settingSection(title: "CATEGORY") {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(categories, id: \.0) { item in
                  choiceChip(item.1, selected: category == item.0) { category = item.0 }
                }
              }
            }
          }

          settingSection(title: "PUBLISH AS") {
            VStack(spacing: 10) {
              identityChoice(
                value: "ghost", title: "Ghost", subtitle: "Anonymous. Your profile will not be shown.", icon: "theatermask.and.paintbrush"
              )
              identityChoice(
                value: "author", title: "Author", subtitle: "Show your profile and username.", icon: "person.crop.circle"
              )
            }
          }

          settingSection(title: "APPROXIMATE LOCATION") {
            TextField("Neighborhood or city (optional)", text: $approximateLocation)
              .textContentType(.addressCity)
              .textInputAutocapitalization(.words)
              .padding(.horizontal, 14)
              .frame(height: 48)
              .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Color.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          Button {
            publish()
          } label: {
            HStack(spacing: 9) {
              if isPublishing { ProgressView().tint(.white) }
              Text(isPublishing ? "Placing…" : "Place on Wall")
                .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(MIRATheme.Color.forest, in: Capsule())
          }
          .buttonStyle(.miraPress)
          .disabled(cleanBody.isEmpty || isPublishing)
          .opacity(cleanBody.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("New Note")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { isTextFocused = false }
        }
      }
    }
  }

  private var livePreview: some View {
    let preview = MIRAWallNote(
      id: "preview", wallId: "global", publishingIdentity: identity,
      body: cleanBody.isEmpty ? "What do you want to leave on the wall?" : cleanBody,
      category: category.isEmpty ? nil : category, colorToken: colorToken, styleToken: styleToken,
      worldX: 0, worldY: 0, width: 220, height: styleToken == "vertical_card" ? 270 : 220,
      rotation: 0, zIndex: 0, approximateLocation: nil, createdAt: "", updatedAt: nil,
      saveCount: 0, reactionCount: 0, replyCount: 0, reactedByViewer: false, savedByViewer: false, authorPreview: nil
    )
    return MIRAWallNoteSurface(note: preview, zoom: 1)
      .frame(width: 220, height: styleToken == "vertical_card" ? 270 : 220)
      .opacity(cleanBody.isEmpty ? 0.60 : 1)
      .padding(.vertical, 8)
  }

  private var cleanBody: String { bodyText.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func settingSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func choiceChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(selected ? Color.white : MIRATheme.Color.textPrimary)
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(selected ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft, in: Capsule())
    }
    .buttonStyle(.plain)
  }

  private func identityChoice(value: String, title: String, subtitle: String, icon: String) -> some View {
    Button {
      identity = value
    } label: {
      HStack(spacing: 13) {
        Image(systemName: icon)
          .font(.system(size: 19, weight: .semibold))
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.system(size: 15, weight: .bold))
          Text(subtitle).font(.system(size: 12)).foregroundStyle(MIRATheme.Color.textSecondary)
        }
        Spacer()
        Image(systemName: identity == value ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(identity == value ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(14)
      .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func publish() {
    let text = cleanBody
    guard !text.isEmpty, !isPublishing else { return }
    isPublishing = true
    errorMessage = nil
    let noteWidth = styleToken == "vertical_card" ? 176.0 : 190.0
    let noteHeight = styleToken == "vertical_card" ? 236.0 : 190.0
    let jitterX = Double.random(in: -90...90)
    let jitterY = Double.random(in: -120...120)
    let body = MIRACreateWallNoteBody(
      wallId: "global", publishingIdentity: identity, body: text,
      category: category.isEmpty ? nil : category, colorToken: colorToken, styleToken: styleToken,
      worldX: Double(camera.center.x) - noteWidth * 0.5 + jitterX,
      worldY: Double(camera.center.y) - noteHeight * 0.5 + jitterY,
      width: noteWidth, height: noteHeight, rotation: Double.random(in: -2.4...2.4),
      approximateLocation: approximateLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : approximateLocation
    )
    Task {
      do {
        _ = try await onPublish(body)
        await MainActor.run { dismiss() }
      } catch {
        await MainActor.run {
          isPublishing = false
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

private struct MIRAWallNoteDetailView: View {
  @State private var note: MIRAWallNote
  let api: MIRAAPIClient
  @ObservedObject var model: MIRAWallNotesModel
  let onChanged: (MIRAWallNote) -> Void
  let onClose: () -> Void

  @State private var replies: [MIRAWallReply] = []
  @State private var replyText = ""
  @State private var replyAsGhost = false
  @State private var isLoadingReplies = false
  @State private var isMutating = false
  @State private var errorMessage: String?
  @State private var showReport = false
  @FocusState private var replyFocused: Bool

  init(
    note: MIRAWallNote,
    api: MIRAAPIClient,
    model: MIRAWallNotesModel,
    onChanged: @escaping (MIRAWallNote) -> Void,
    onClose: @escaping () -> Void
  ) {
    _note = State(initialValue: note)
    self.api = api
    self.model = model
    self.onChanged = onChanged
    self.onClose = onClose
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          MIRAWallNoteSurface(note: note, zoom: 1.15)
            .frame(maxWidth: 330)
            .aspectRatio(note.width / max(note.height, 1), contentMode: .fit)
            .rotationEffect(.degrees(note.rotation * 0.16))

          authorMetadata
          actionRow

          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(Color.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          Divider().opacity(0.45)
          replyComposer
          repliesSection
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MIRATheme.Color.surface)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .bold))
              .frame(width: 38, height: 38)
              .background(MIRATheme.Color.surfaceSoft, in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Close note")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Report", systemImage: "exclamationmark.triangle") { showReport = true }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 16, weight: .bold))
              .frame(width: 38, height: 38)
              .background(MIRATheme.Color.surfaceSoft, in: Circle())
          }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { replyFocused = false }
        }
      }
      .task { await loadReplies() }
      .sheet(isPresented: $showReport) {
        MIRAReportSheet(
          target: MIRAReportTarget(
            targetType: "wall_note", targetId: note.id,
            ownerUserId: note.authorPreview?.userId,
            title: "Wall note", subtitle: String(note.body.prefix(90))
          ),
          api: api,
          onSubmitted: { _ in showReport = false },
          onClose: { showReport = false }
        )
        .presentationDetents([.large])
      }
    }
    .frame(maxWidth: 390, maxHeight: 720)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  @ViewBuilder
  private var authorMetadata: some View {
    HStack(spacing: 12) {
      if note.isGhost {
        Image(systemName: "theatermask.and.paintbrush")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 42, height: 42)
          .background(MIRATheme.Color.surfaceSoft, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text("Ghost Note").font(.system(size: 15, weight: .bold))
          Text(metadataSubtitle).font(.system(size: 12)).foregroundStyle(MIRATheme.Color.textSecondary)
        }
      } else if let author = note.authorPreview {
        if let userID = author.userId, !userID.isEmpty {
          NavigationLink(destination: UserProfileNativeView(userId: userID, api: api)) {
            HStack(spacing: 12) {
              MIRAWallAvatar(url: author.avatarUrl)
              VStack(alignment: .leading, spacing: 2) {
                Text(author.title).font(.system(size: 15, weight: .bold))
                Text(metadataSubtitle).font(.system(size: 12)).foregroundStyle(MIRATheme.Color.textSecondary)
              }
            }
          }
          .buttonStyle(.plain)
        } else {
          HStack(spacing: 12) {
            MIRAWallAvatar(url: author.avatarUrl)
            VStack(alignment: .leading, spacing: 2) {
              Text(author.title).font(.system(size: 15, weight: .bold))
              Text(metadataSubtitle).font(.system(size: 12)).foregroundStyle(MIRATheme.Color.textSecondary)
            }
          }
        }
      }
      Spacer()
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
  }

  private var metadataSubtitle: String {
    [note.approximateLocation, relativeTime(note.createdAt)].compactMap { value in
      let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return clean.isEmpty ? nil : clean
    }.joined(separator: " · ")
  }

  private var actionRow: some View {
    HStack(spacing: 6) {
      detailAction(
        title: "Felt this", count: note.reactionCount,
        icon: note.reactedByViewer ? "heart.fill" : "heart",
        tint: note.reactedByViewer ? MIRATheme.Color.like : MIRATheme.Color.textPrimary
      ) { toggleReaction() }
      detailAction(
        title: "Save", count: note.saveCount,
        icon: note.savedByViewer ? "bookmark.fill" : "bookmark",
        tint: MIRATheme.Color.textPrimary
      ) { toggleSaved() }
      detailAction(title: "Reply", count: note.replyCount, icon: "bubble.left", tint: MIRATheme.Color.textPrimary) {
        replyFocused = true
      }
      ShareLink(item: URL(string: "https://captro.app/wall/notes/\(note.id)")!) {
        VStack(spacing: 5) {
          Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .semibold))
          Text("Share").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 52)
      }
    }
    .disabled(isMutating)
  }

  private func detailAction(title: String, count: Int, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        HStack(spacing: 3) {
          Image(systemName: icon).font(.system(size: 18, weight: .semibold))
          if count > 0 { Text("\(count)").font(.system(size: 11, weight: .bold)) }
        }
        Text(title).font(.system(size: 10, weight: .semibold))
      }
      .foregroundStyle(tint)
      .frame(maxWidth: .infinity, minHeight: 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(.miraPress)
  }

  private var replyComposer: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Replies").font(.system(size: 17, weight: .bold, design: .serif))
        Spacer()
        Toggle("Ghost", isOn: $replyAsGhost)
          .labelsHidden()
          .tint(MIRATheme.Color.forest)
        Text(replyAsGhost ? "Reply as Ghost" : "Reply as Author")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      HStack(alignment: .bottom, spacing: 9) {
        TextField("Leave a thoughtful reply", text: $replyText, axis: .vertical)
          .focused($replyFocused)
          .lineLimit(1...4)
          .padding(.horizontal, 13)
          .padding(.vertical, 11)
          .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .onChange(of: replyText) { _, value in
            if value.count > 300 { replyText = String(value.prefix(300)) }
          }
        Button { sendReply() } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(MIRATheme.Color.forest, in: Circle())
        }
        .buttonStyle(.miraPress)
        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isMutating)
      }
    }
  }

  private var repliesSection: some View {
    LazyVStack(spacing: 10) {
      if isLoadingReplies && replies.isEmpty {
        ProgressView().padding(.vertical, 18)
      } else if replies.isEmpty {
        Text("No replies yet.")
          .font(.system(size: 13))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .padding(.vertical, 14)
      } else {
        ForEach(replies) { reply in
          HStack(alignment: .top, spacing: 10) {
            if reply.isGhost {
              Image(systemName: "theatermask.and.paintbrush")
                .frame(width: 34, height: 34)
                .background(MIRATheme.Color.surfaceSoft, in: Circle())
            } else {
              MIRAWallAvatar(url: reply.authorPreview?.avatarUrl, size: 34)
            }
            VStack(alignment: .leading, spacing: 4) {
              Text(reply.isGhost ? "Ghost" : (reply.authorPreview?.title ?? "Captro member"))
                .font(.system(size: 12, weight: .bold))
              Text(reply.body)
                .font(.system(size: 14))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(12)
          .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
      }
    }
  }

  private func toggleReaction() {
    guard !isMutating else { return }
    isMutating = true
    let requested = !note.reactedByViewer
    Task {
      do {
        let updated = try await model.setReaction(note: note, reacted: requested)
        await MainActor.run { note = updated; onChanged(updated); isMutating = false }
      } catch {
        await MainActor.run { errorMessage = error.localizedDescription; isMutating = false }
      }
    }
  }

  private func toggleSaved() {
    guard !isMutating else { return }
    isMutating = true
    let requested = !note.savedByViewer
    Task {
      do {
        let updated = try await model.setSaved(note: note, saved: requested)
        await MainActor.run { note = updated; onChanged(updated); isMutating = false }
      } catch {
        await MainActor.run { errorMessage = error.localizedDescription; isMutating = false }
      }
    }
  }

  private func loadReplies() async {
    isLoadingReplies = true
    defer { isLoadingReplies = false }
    do { replies = try await model.replies(for: note) }
    catch { errorMessage = error.localizedDescription }
  }

  private func sendReply() {
    let clean = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !isMutating else { return }
    isMutating = true
    Task {
      do {
        let reply = try await model.addReply(note: note, body: clean, identity: replyAsGhost ? "ghost" : "author")
        await MainActor.run {
          replies.append(reply)
          note = note.updating(replyCount: note.replyCount + 1)
          onChanged(note)
          replyText = ""
          isMutating = false
        }
      } catch {
        await MainActor.run { errorMessage = error.localizedDescription; isMutating = false }
      }
    }
  }

  private func relativeTime(_ value: String) -> String? {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: value) else { return nil }
    let seconds = max(0, Date().timeIntervalSince(date))
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
    if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
    return "\(Int(seconds / 86400))d ago"
  }
}

private struct MIRAWallAvatar: View {
  let url: String?
  var size: CGFloat = 42

  var body: some View {
    MIRACachedImage(url: url, maxPixelSize: size * 3) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      MIRATheme.Color.mediaPlaceholder
        .overlay(Image(systemName: "person.fill").foregroundStyle(MIRATheme.Color.textMuted))
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}
