import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MIRAWallNotesModel: ObservableObject {
  @Published private(set) var notes: [MIRAWallNote] = []
  @Published private(set) var overview: MIRAWallOverview?
  @Published private(set) var currentWallID = MIRAWallDestination.global.rawValue
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?

  private let api: MIRAAPIClient
  private var spatialIndex = MIRAWallSpatialIndex()
  private var displayFrames: [String: CGRect] = [:]
  private var inFlightSignature: String?
  private var lastLoadedSignature: String?
  private var activeViewSignature: String?

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func visibleNotes(in bounds: CGRect) -> [MIRAWallNote] {
    spatialIndex.notes(in: bounds)
  }

  func note(at point: CGPoint) -> MIRAWallNote? {
    spatialIndex.note(at: point)
  }

  func displayFrame(for note: MIRAWallNote) -> CGRect {
    displayFrames[note.id] ?? MIRAWallNotePresentationResolver.wallFrame(for: note)
  }

  func loadOverview(wallID: String, force: Bool = false) async {
    guard force || overview?.wallId != wallID else { return }
    var components = URLComponents()
    components.path = "/wall/overview"
    components.queryItems = [URLQueryItem(name: "wall_id", value: wallID)]
    do {
      let response: MIRAWallOverview = try await api.get(components.string ?? "/wall/overview")
      guard currentWallID == wallID else { return }
      overview = response
    } catch is CancellationError {
      return
    } catch {
      if notes.isEmpty { errorMessage = error.localizedDescription }
    }
  }

  func load(
    bounds: CGRect,
    zoom: CGFloat,
    wallID: String,
    filter: String,
    query: String,
    force: Bool = false
  ) async {
    let expanded = bounds.insetBy(dx: -max(420, bounds.width * 0.35), dy: -max(600, bounds.height * 0.35))
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let viewSignature = "\(wallID):\(filter):\(cleanQuery)"
    if activeViewSignature != viewSignature {
      notes = []
      displayFrames = [:]
      spatialIndex.rebuild(with: [])
      lastLoadedSignature = nil
      inFlightSignature = nil
      activeViewSignature = viewSignature
    }
    let signature = [
      wallID,
      String(Int(expanded.minX / 320)), String(Int(expanded.maxX / 320)),
      String(Int(expanded.minY / 320)), String(Int(expanded.maxY / 320)),
      String(format: "%.1f", zoom), filter, cleanQuery,
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
      URLQueryItem(name: "wall_id", value: wallID),
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
      guard currentWallID == wallID, activeViewSignature == viewSignature else { return }
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
    await loadOverview(wallID: response.note.wallId, force: true)
    return response.note
  }

  func setReaction(note: MIRAWallNote, reacted: Bool) async throws -> MIRAWallNote {
    let optimistic = note.updating(
      reacted: reacted,
      reactionCount: max(0, note.reactionCount + (reacted ? 1 : -1))
    )
    update(optimistic)
    do {
      let response: MIRAWallToggleResponse = try await api.post("/wall/notes/\(note.id)/reaction", body: MIRAWallReactionBody(reacted: reacted))
      let reconciled = note.updating(
        reacted: response.reacted ?? reacted,
        reactionCount: response.reactionCount ?? optimistic.reactionCount
      )
      update(reconciled)
      return reconciled
    } catch {
      update(note)
      throw error
    }
  }

  func setSaved(note: MIRAWallNote, saved: Bool) async throws -> MIRAWallNote {
    let optimistic = note.updating(
      saved: saved,
      saveCount: max(0, note.saveCount + (saved ? 1 : -1))
    )
    update(optimistic)
    do {
      let response: MIRAWallToggleResponse = try await api.post("/wall/notes/\(note.id)/save", body: MIRAWallSaveBody(saved: saved))
      let reconciled = note.updating(
        saved: response.saved ?? saved,
        saveCount: response.saveCount ?? optimistic.saveCount
      )
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

  func setSigned(
    note: MIRAWallNote,
    signed: Bool,
    drawing: MIRAWallSignatureDrawing? = nil
  ) async throws -> MIRAWallNote {
    let optimistic = note.updating(
      signed: signed,
      signatureCount: max(0, note.resolvedSignatureCount + (signed ? 1 : -1))
    )
    update(optimistic)
    do {
      let response: MIRAWallSignatureToggleResponse = try await api.post(
        "/wall/notes/\(note.id)/signature",
        body: MIRAWallSignatureBody(signed: signed, drawing: drawing)
      )
      let reconciled = note.updating(signed: response.signed, signatureCount: response.signatureCount)
      update(reconciled)
      return reconciled
    } catch {
      update(note)
      throw error
    }
  }

  func signers(
    for note: MIRAWallNote,
    before: String? = nil,
    limit: Int = 30
  ) async throws -> MIRAWallSignersResponse {
    var components = URLComponents()
    components.path = "/wall/notes/\(note.id)/signatures"
    components.queryItems = [
      URLQueryItem(name: "limit", value: String(max(1, min(100, limit)))),
    ]
    if let before, !before.isEmpty {
      components.queryItems?.append(URLQueryItem(name: "before", value: before))
    }
    return try await api.get(components.string ?? "/wall/notes/\(note.id)/signatures?limit=30")
  }

  func contributions(
    for note: MIRAWallNote,
    after: String? = nil,
    limit: Int = 30
  ) async throws -> MIRAWallContributionsResponse {
    var components = URLComponents()
    components.path = "/wall/notes/\(note.id)/contributions"
    components.queryItems = [
      URLQueryItem(name: "limit", value: String(max(1, min(100, limit)))),
    ]
    if let after, !after.isEmpty {
      components.queryItems?.append(URLQueryItem(name: "after", value: after))
    }
    return try await api.get(components.string ?? "/wall/notes/\(note.id)/contributions?limit=30")
  }

  func addContribution(note: MIRAWallNote, body: String, identity: String) async throws -> MIRAWallContribution {
    let response: MIRAWallContributionResponse = try await api.post(
      "/wall/notes/\(note.id)/contributions",
      body: MIRAWallReplyBody(body: body, publishingIdentity: identity)
    )
    let count = response.contributionCount ?? note.resolvedContributionCount + 1
    update(note.updating(replyCount: count, contributionCount: count))
    return response.contribution
  }

  func setCollaboration(note: MIRAWallNote, allowed: Bool) async throws -> MIRAWallNote {
    let response: MIRAWallCollaborationResponse = try await api.patch(
      "/wall/notes/\(note.id)/collaboration",
      body: MIRAWallCollaborationBody(allowContributions: allowed)
    )
    let updated = note.updating(allowContributions: response.allowContributions)
    update(updated)
    return updated
  }

  private func merge(_ incoming: [MIRAWallNote], around bounds: CGRect) {
    var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    incoming.forEach { note in
      if let previous = byID[note.id],
         MIRAWallNotePresentationResolver.wallFrame(for: previous)
           != MIRAWallNotePresentationResolver.wallFrame(for: note) {
        displayFrames.removeValue(forKey: note.id)
      }
      byID[note.id] = note
    }
    let retention = bounds.insetBy(dx: -max(5000, bounds.width * 2.5), dy: -max(5000, bounds.height * 2.5))
    let viewportCenter = CGPoint(x: bounds.midX, y: bounds.midY)
    let retained = byID.values
      .filter { note in
        retention.intersects(MIRAWallNotePresentationResolver.wallFrame(for: note))
      }
      .sorted { left, right in
        let leftFrame = MIRAWallNotePresentationResolver.wallFrame(for: left)
        let rightFrame = MIRAWallNotePresentationResolver.wallFrame(for: right)
        let leftVisible = bounds.intersects(leftFrame)
        let rightVisible = bounds.intersects(rightFrame)
        if leftVisible != rightVisible { return leftVisible }

        let leftDistance = squaredDistance(from: leftFrame, to: viewportCenter)
        let rightDistance = squaredDistance(from: rightFrame, to: viewportCenter)
        if leftDistance != rightDistance { return leftDistance < rightDistance }
        if left.zIndex != right.zIndex { return left.zIndex < right.zIndex }
        if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
        return left.id < right.id
      }
    notes = Array(retained.prefix(1800))
    rebuildDisplayLayout()
  }

  private func update(_ note: MIRAWallNote) {
    if let index = notes.firstIndex(where: { $0.id == note.id }) {
      let previousFrame = MIRAWallNotePresentationResolver.wallFrame(for: notes[index])
      notes[index] = note
      let nextFrame = MIRAWallNotePresentationResolver.wallFrame(for: note)
      if previousFrame == nextFrame, spatialIndex.replace(note) {
        return
      }
      displayFrames.removeValue(forKey: note.id)
    } else {
      notes.append(note)
    }
    rebuildDisplayLayout()
  }

  private func rebuildDisplayLayout() {
    displayFrames = MIRAWallReadableLayout.frames(for: notes, preserving: displayFrames)
    spatialIndex.rebuild(with: notes, frameOverrides: displayFrames)
  }

  private func squaredDistance(from frame: CGRect, to point: CGPoint) -> CGFloat {
    let dx = frame.midX - point.x
    let dy = frame.midY - point.y
    return dx * dx + dy * dy
  }
}

public struct WallOfNotesNativeView: View {
  private let globalWallID = MIRAWallDestination.global.id
  private let api: MIRAAPIClient
  private let storiesModel: DiscoverNativeModel
  @StateObject private var model: MIRAWallNotesModel
  @State private var camera = MIRAWallCamera()
  @State private var panStart: MIRAWallCamera?
  @State private var magnifyStart: MIRAWallCamera?
  @State private var liveMagnification: CGFloat = 1
  @State private var liveMagnificationAnchor = UnitPoint.center
  @State private var selectedNote: MIRAWallNote?
  @State private var liftedNoteID: String?
  @State private var pressedNoteID: String?
  @State private var isCreating = false
  @State private var isSearching = false
  @State private var query = ""
  @State private var selectedFilter = "all"
  @State private var showFilters = false
  @State private var initialFrameWallID: String?
  @State private var placementNoteID: String?
  @State private var selectedStoryGroup: MIRAStoryGroup?
  @State private var storyReportTarget: MIRAReportTarget?
  @State private var isStoryReportSheetPresented = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(api: MIRAAPIClient, storiesModel: DiscoverNativeModel) {
    self.api = api
    self.storiesModel = storiesModel
    _model = StateObject(wrappedValue: MIRAWallNotesModel(api: api))
  }

  public var body: some View {
    VStack(spacing: 0) {
      wallHeader
      MIRAStoriesRailNativeView(model: storiesModel) { group in
        selectedStoryGroup = group
      }

      GeometryReader { proxy in
        let viewport = proxy.size
        let bounds = camera.worldBounds(viewport: viewport)
        ZStack {
          MIRAWallBackground(camera: camera, viewport: viewport)
            .ignoresSafeArea()

          ZStack {
            wallNotes(bounds: bounds, viewport: viewport)

            if shouldShowWallStartSign {
              wallStartSign(viewport: viewport)
            } else if shouldShowFilteredEmptySign {
              filteredEmptySign(viewport: viewport)
            }
          }
          .scaleEffect(liveMagnification, anchor: liveMagnificationAnchor)
          .animation(nil, value: liveMagnification)

          chrome

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
            openNote(note)
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
          guard !Task.isCancelled, initialFrameWallID == globalWallID else { return }
          await model.load(
            bounds: bounds,
            zoom: camera.scale,
            wallID: globalWallID,
            filter: selectedFilter,
            query: query
          )
        }
        .task(id: globalWallID) {
          initialFrameWallID = nil
          await model.loadOverview(wallID: globalWallID, force: true)
          guard !Task.isCancelled else { return }
          if let overview = model.overview {
            camera = MIRAWallLayout.initialCamera(
              noteBounds: overview.noteBounds,
              noteCount: overview.totalCount,
              viewport: viewport,
              includeStartSign: overview.totalCount < 5
            )
          } else {
            camera = MIRAWallCamera(scale: 0.92)
          }
          initialFrameWallID = globalWallID
          await model.load(
            bounds: camera.worldBounds(viewport: viewport),
            zoom: camera.scale,
            wallID: globalWallID,
            filter: selectedFilter,
            query: query,
            force: true
          )
        }
        .sheet(isPresented: $isCreating) {
          MIRACreateWallNoteView(camera: camera, api: api) { body in
            let note = try await model.create(body)
            placementNoteID = note.id
            withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
              let frame = model.displayFrame(for: note)
              camera.center = CGPoint(x: frame.midX, y: frame.midY)
              camera.scale = max(camera.scale, 0.72)
            }
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(800))
              placementNoteID = nil
            }
            return note
          }
          .presentationDetents([.large])
          .presentationCornerRadius(30)
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
              .frame(maxHeight: 470)
            }
          }
        }
      }
      .background(MIRATheme.Color.launchBackground)
    }
    .background(MIRATheme.Color.surface)
    .miraFadeScaleOverlay(
      isPresented: Binding(
        get: { selectedNote != nil },
        set: {
          if !$0 {
            selectedNote = nil
            liftedNoteID = nil
            pressedNoteID = nil
          }
        }
      ),
      scrimOpacity: 0.18
    ) { dismiss in
      if let note = selectedNote {
        MIRAWallNoteDetailView(
          note: note,
          api: api,
          model: model,
          onChanged: { updated in
            selectedNote = updated
          },
          onClose: dismiss
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
      }
    }
    .miraStatusBarHidden(selectedStoryGroup != nil)
    .toolbar(storyTabBarVisibility, for: .tabBar)
    .miraFullScreenOverlay(item: $selectedStoryGroup, background: .black) { group, dismissStory in
      StoryViewerNativeView(
        group: group,
        allGroups: storiesModel.stories,
        api: api,
        onClose: dismissStory,
        onReportStory: { target in
          dismissStory()
          DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.fullScreenClose) {
            storyReportTarget = target
            withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
              isStoryReportSheetPresented = true
            }
          }
        }
      )
    }
    .miraBottomSheet(
      isPresented: $isStoryReportSheetPresented,
      preferredHeightFraction: 0.72,
      maxHeight: 640,
      onDismissed: { storyReportTarget = nil }
    ) { dismissReport in
      if let storyReportTarget {
        MIRAReportSheet(
          target: storyReportTarget,
          api: api,
          onSubmitted: { _ in },
          onClose: dismissReport
        )
      } else {
        Color.clear
      }
    }
  }

  private var storyTabBarVisibility: Visibility {
    selectedStoryGroup == nil && !isStoryReportSheetPresented && selectedNote == nil ? .visible : .hidden
  }

  @ViewBuilder
  private func wallNotes(bounds: CGRect, viewport: CGSize) -> some View {
    // Include rotated paper edges, attachments, and cast shadows before a tile
    // reaches the viewport so low-zoom cards never appear sliced.
    let preload = max(320, 420 / max(camera.scale, 0.2))
    let visible = model.visibleNotes(in: bounds.insetBy(dx: -preload, dy: -preload))
    ZStack {
      ForEach(visible) { note in
        let presentation = MIRAWallNotePresentationResolver.resolve(note)
        let frame = model.displayFrame(for: note)
        let center = camera.screenPoint(forWorld: CGPoint(x: frame.midX, y: frame.midY), viewport: viewport)
        MIRAWallNoteTile(
          note: note,
          isNew: placementNoteID == note.id,
          wallScale: camera.scale,
          isLifted: liftedNoteID == note.id || selectedNote?.id == note.id,
          isPressed: pressedNoteID == note.id
        )
        .frame(width: presentation.size.width, height: presentation.size.height)
        .rotationEffect(.degrees(note.rotation + presentation.microRotation))
        .scaleEffect(camera.scale)
        .position(center)
        .allowsHitTesting(false)
        .zIndex(Double(note.zIndex) + (liftedNoteID == note.id || selectedNote?.id == note.id ? 10_000 : 0))
      }
    }
  }

  private func openNote(_ note: MIRAWallNote) {
    guard selectedNote == nil, liftedNoteID == nil else { return }
    pressedNoteID = nil
    withAnimation(CaptroMotion.buttonPressAnimation(reduceMotion: reduceMotion)) {
      liftedNoteID = note.id
    }

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 45))
      guard liftedNoteID == note.id, selectedNote == nil else { return }
      withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
        selectedNote = note
      }
    }
  }

  private var wallHeader: some View {
    HStack(spacing: 10) {
      if isSearching {
        TextField("Search notes", text: $query)
          .textFieldStyle(.plain)
          .font(.system(size: 15, weight: .medium))
          .padding(.horizontal, 14)
          .frame(height: 40)
          .background(MIRATheme.Color.appBackground, in: Capsule())
          .submitLabel(.search)
          .transition(.opacity.combined(with: .move(edge: .trailing)))
      } else {
        Text("Wall of Notes")
          .font(.system(size: 25, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .transition(.opacity)

        Spacer(minLength: 8)
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
    .padding(.vertical, 8)
    .frame(minHeight: 58)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var chrome: some View {
    VStack(spacing: 0) {
      Spacer()

      HStack {
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
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 16)
    }
    .allowsHitTesting(true)
  }

  private func wallIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(width: 38, height: 38)
        .background(MIRATheme.Color.surface.opacity(0.94), in: Circle())
        .overlay(Circle().stroke(MIRATheme.Color.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
    }
    .frame(width: 44, height: 44)
    .buttonStyle(.miraPress)
  }

  private func errorState(message: String, bounds: CGRect) -> some View {
    VStack(spacing: 12) {
      Text("Couldn't load this part of the wall.")
        .font(.system(size: 16, weight: .semibold))
      Text(message)
        .font(.system(size: 13))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .multilineTextAlignment(.center)
      Button("Retry") {
        Task {
          await model.load(
            bounds: bounds,
            zoom: camera.scale,
            wallID: globalWallID,
            filter: selectedFilter,
            query: query,
            force: true
          )
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(MIRATheme.Color.forest)
    }
    .padding(24)
    .background(MIRATheme.Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .padding(24)
  }

  private func panGesture(viewport: CGSize) -> some Gesture {
    // Keep a real movement threshold so the wall pan recognizer does not enter
    // its changed state on a normal note tap.
    DragGesture(minimumDistance: 6, coordinateSpace: .local)
      .onChanged { value in
        guard magnifyStart == nil else { return }
        if panStart == nil {
          panStart = camera
          let world = camera.worldPoint(forScreen: value.startLocation, viewport: viewport)
          pressedNoteID = model.note(at: world)?.id
        }

        let distance = hypot(value.translation.width, value.translation.height)
        guard distance > 4, let start = panStart else { return }
        pressedNoteID = nil
        camera.center = CGPoint(
          x: start.center.x - value.translation.width / max(start.scale, 0.2),
          y: start.center.y - value.translation.height / max(start.scale, 0.2)
        )
      }
      .onEnded { value in
        let distance = hypot(value.translation.width, value.translation.height)
        pressedNoteID = nil
        guard let start = panStart else { return }
        panStart = nil
        guard distance > 4 else { return }

        let projected = CGSize(
          width: value.predictedEndTranslation.width - value.translation.width,
          height: value.predictedEndTranslation.height - value.translation.height
        )
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.91)) {
          camera.center.x -= projected.width * 0.18 / max(start.scale, 0.2)
          camera.center.y -= projected.height * 0.18 / max(start.scale, 0.2)
        }
      }
  }

  private func magnifyGesture(viewport: CGSize) -> some Gesture {
    MagnifyGesture(minimumScaleDelta: 0.005)
      .onChanged { value in
        if magnifyStart == nil {
          magnifyStart = camera
          panStart = nil
          pressedNoteID = nil
        }
        guard let start = magnifyStart else { return }
        let targetScale = min(max(start.scale * value.magnification, 0.20), 2.50)
        liveMagnification = targetScale / max(start.scale, 0.001)
        liveMagnificationAnchor = value.startAnchor
      }
      .onEnded { value in
        guard let start = magnifyStart else { return }
        let anchor = CGPoint(x: value.startAnchor.x * viewport.width, y: value.startAnchor.y * viewport.height)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          camera = start.zoomed(
            to: start.scale * value.magnification,
            around: anchor,
            viewport: viewport
          )
          liveMagnification = 1
          liveMagnificationAnchor = .center
          magnifyStart = nil
        }
      }
  }

  private func loadKey(bounds: CGRect) -> String {
    [
      Int(bounds.midX / 260), Int(bounds.midY / 260), Int(camera.scale * 10),
    ].map(String.init).joined(separator: ":")
      + ":\(selectedFilter):\(query)"
  }

  private var wallNoteCount: Int { model.overview?.totalCount ?? model.notes.count }

  private var shouldShowWallStartSign: Bool {
    initialFrameWallID == globalWallID && wallNoteCount < 5 && selectedFilter == "all" && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isLoading
  }

  private var shouldShowFilteredEmptySign: Bool {
    initialFrameWallID == globalWallID && model.notes.isEmpty && !model.isLoading && model.errorMessage == nil && !shouldShowWallStartSign
  }


  private func wallStartSign(viewport: CGSize) -> some View {
    let rect = MIRAWallLayout.startSignRect(noteBounds: model.overview?.noteBounds, noteCount: wallNoteCount)
    let center = camera.screenPoint(forWorld: CGPoint(x: rect.midX, y: rect.midY), viewport: viewport)
    return MIRAWallStartSign(onAdd: { isCreating = true })
    .frame(width: rect.width, height: rect.height)
    .scaleEffect(camera.scale)
    .position(center)
    .zIndex(20_000)
  }

  private func filteredEmptySign(viewport: CGSize) -> some View {
    let center = camera.screenPoint(forWorld: camera.center, viewport: viewport)
    return MIRAWallFilteredEmptySign {
      selectedFilter = "all"
      query = ""
    }
    .frame(width: 260, height: 150)
    .scaleEffect(max(0.72, min(1, camera.scale)))
    .position(center)
    .zIndex(20_000)
  }
}

private struct MIRAWallStartSign: View {
  let onAdd: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("THE WALL IS JUST BEGINNING")
        .font(.system(size: 15, weight: .semibold, design: .serif))
        .tracking(0.8)

      Text("Leave a thought, recommendation, confession, question, or something worth remembering.")
        .font(.system(size: 13, weight: .regular, design: .serif))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)

      Button("Place the next note", action: onAdd)
      .font(.system(size: 12, weight: .bold))
      .underline()
    }
    .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.08))
    .padding(.horizontal, 22)
    .padding(.vertical, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color(red: 0.975, green: 0.955, blue: 0.90))
    .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 0.8))
    .overlay(alignment: .top) {
      Capsule()
        .fill(Color.white.opacity(0.58))
        .frame(width: 68, height: 13)
        .offset(y: -7)
        .rotationEffect(.degrees(-1.2))
    }
    .shadow(color: .black.opacity(0.14), radius: 5, x: 1, y: 4)
    .rotationEffect(.degrees(0.7))
    .accessibilityElement(children: .contain)
  }
}

private struct MIRAWallFilteredEmptySign: View {
  let onClear: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("A QUIET CORNER")
        .font(.system(size: 14, weight: .semibold, design: .serif))
        .tracking(0.7)
      Text("No real notes match this view yet.")
        .font(.system(size: 13, design: .serif))
      Button("Show all notes", action: onClear)
        .font(.system(size: 12, weight: .bold))
        .underline()
    }
    .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.08))
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color(red: 0.965, green: 0.945, blue: 0.89))
    .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 0.8))
    .shadow(color: .black.opacity(0.12), radius: 4, x: 1, y: 3)
    .rotationEffect(.degrees(-0.8))
  }
}

private enum MIRAWallFilter: String, CaseIterable, Identifiable {
  case all, ghost, author, recent, popular, saved, question, confession, food, advice, life

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
    }
  }
}

private struct MIRAWallBackground: View {
  let camera: MIRAWallCamera
  let viewport: CGSize

  var body: some View {
    Canvas { context, size in
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(Color(red: 0.932, green: 0.913, blue: 0.868))
      )

      let tileWorldSize: CGFloat = 212
      let bounds = camera.worldBounds(viewport: size, preload: tileWorldSize)
      let minTileX = Int(floor(bounds.minX / tileWorldSize))
      let maxTileX = Int(ceil(bounds.maxX / tileWorldSize))
      let minTileY = Int(floor(bounds.minY / tileWorldSize))
      let maxTileY = Int(ceil(bounds.maxY / tileWorldSize))
      let fiberCount = camera.scale < 0.34 ? 1 : 2
      let materialScale = min(1.18, max(0.62, camera.scale))

      for tileY in minTileY...maxTileY {
        for tileX in minTileX...maxTileX {
          let signedSeed = (tileX &* 73_856_093) ^ (tileY &* 19_349_663)
          let seed = UInt64(bitPattern: Int64(signedSeed))

          for index in 0..<fiberCount {
            let world = CGPoint(
              x: CGFloat(tileX) * tileWorldSize + tileWorldSize * MIRAWallBackgroundNoise.unit(seed, index * 5 + 1),
              y: CGFloat(tileY) * tileWorldSize + tileWorldSize * MIRAWallBackgroundNoise.unit(seed, index * 5 + 2)
            )
            let point = camera.screenPoint(forWorld: world, viewport: size)
            let length = (2.2 + 4.8 * MIRAWallBackgroundNoise.unit(seed, index * 5 + 3)) * materialScale
            let angle = (MIRAWallBackgroundNoise.unit(seed, index * 5 + 4) - 0.5) * 0.72
            var fiber = Path()
            fiber.move(to: point)
            fiber.addLine(to: CGPoint(
              x: point.x + cos(angle) * length,
              y: point.y + sin(angle) * length
            ))
            let fiberColor = index.isMultiple(of: 2)
              ? Color(red: 0.42, green: 0.31, blue: 0.18).opacity(0.022)
              : Color(red: 0.34, green: 0.40, blue: 0.38).opacity(0.016)
            context.stroke(
              fiber,
              with: .color(fiberColor),
              style: StrokeStyle(lineWidth: 0.42, lineCap: .round)
            )
          }

          if seed % 17 == 0 {
            let world = CGPoint(
              x: CGFloat(tileX) * tileWorldSize + tileWorldSize * MIRAWallBackgroundNoise.unit(seed, 31),
              y: CGFloat(tileY) * tileWorldSize + tileWorldSize * MIRAWallBackgroundNoise.unit(seed, 32)
            )
            let point = camera.screenPoint(forWorld: world, viewport: size)
            let radius = (1.3 + MIRAWallBackgroundNoise.unit(seed, 33) * 2.1) * materialScale
            var imperfection = Path()
            imperfection.move(to: CGPoint(x: point.x - radius, y: point.y))
            imperfection.addQuadCurve(
              to: CGPoint(x: point.x + radius, y: point.y + radius * 0.18),
              control: CGPoint(x: point.x, y: point.y - radius * 0.52)
            )
            imperfection.addQuadCurve(
              to: CGPoint(x: point.x - radius, y: point.y),
              control: CGPoint(x: point.x, y: point.y + radius * 0.44)
            )
            context.fill(
              imperfection,
              with: .color(Color(red: 0.48, green: 0.34, blue: 0.20).opacity(0.010))
            )
          }
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private enum MIRAWallBackgroundNoise {
  static func seed(for value: String) -> UInt64 {
    value.utf8.reduce(UInt64(0xcbf29ce484222325)) { partial, byte in
      (partial ^ UInt64(byte)) &* 0x100000001b3
    }
  }

  static func unit(_ seed: UInt64, _ salt: Int) -> CGFloat {
    var mixed = seed &+ UInt64(max(0, salt) + 1) &* 0x9E3779B97F4A7C15
    mixed ^= mixed >> 30
    mixed &*= 0xBF58476D1CE4E5B9
    mixed ^= mixed >> 27
    mixed &*= 0x94D049BB133111EB
    mixed ^= mixed >> 31
    return CGFloat(mixed % 10_000) / 10_000
  }
}

private struct MIRAWallDetailBackdrop: View {
  let seed: String

  var body: some View {
    Canvas { context, size in
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(Color(red: 0.944, green: 0.929, blue: 0.895))
      )

      let materialSeed = MIRAWallBackgroundNoise.seed(for: seed)
      for index in 0..<44 {
        let y = size.height * MIRAWallBackgroundNoise.unit(materialSeed, index * 4 + 1)
        let startX = size.width * MIRAWallBackgroundNoise.unit(materialSeed, index * 4 + 2)
        let length = 14 + 48 * MIRAWallBackgroundNoise.unit(materialSeed, index * 4 + 3)
        let rise = (MIRAWallBackgroundNoise.unit(materialSeed, index * 4 + 4) - 0.5) * 4
        var fiber = Path()
        fiber.move(to: CGPoint(x: startX, y: y))
        fiber.addQuadCurve(
          to: CGPoint(x: min(size.width, startX + length), y: y + rise),
          control: CGPoint(x: startX + length * 0.52, y: y - rise * 0.7)
        )
        context.stroke(
          fiber,
          with: .color(Color(red: 0.31, green: 0.24, blue: 0.16).opacity(index.isMultiple(of: 3) ? 0.030 : 0.016)),
          style: StrokeStyle(lineWidth: index.isMultiple(of: 4) ? 0.6 : 0.35, lineCap: .round)
        )
      }

      for index in 0..<13 {
        let point = CGPoint(
          x: size.width * MIRAWallBackgroundNoise.unit(materialSeed, 300 + index * 2),
          y: size.height * MIRAWallBackgroundNoise.unit(materialSeed, 301 + index * 2)
        )
        let radius = 0.7 + MIRAWallBackgroundNoise.unit(materialSeed, 500 + index) * 1.1
        context.fill(
          Path(ellipseIn: CGRect(x: point.x, y: point.y, width: radius, height: radius)),
          with: .color(Color.black.opacity(0.025))
        )
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct MIRAWallDetailNoteStage: View {
  let seed: String

  var body: some View {
    Canvas { context, size in
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(Color(red: 0.884, green: 0.843, blue: 0.765))
      )

      let materialSeed = MIRAWallBackgroundNoise.seed(for: "stage-\(seed)")
      for index in 0..<34 {
        let point = CGPoint(
          x: size.width * MIRAWallBackgroundNoise.unit(materialSeed, index * 3 + 1),
          y: size.height * MIRAWallBackgroundNoise.unit(materialSeed, index * 3 + 2)
        )
        let length = 5 + 14 * MIRAWallBackgroundNoise.unit(materialSeed, index * 3 + 3)
        var grain = Path()
        grain.move(to: point)
        grain.addLine(to: CGPoint(x: min(size.width, point.x + length), y: point.y + 0.8))
        context.stroke(
          grain,
          with: .color(Color(red: 0.36, green: 0.27, blue: 0.17).opacity(index.isMultiple(of: 2) ? 0.045 : 0.025)),
          style: StrokeStyle(lineWidth: 0.5, lineCap: .round)
        )
      }

      for index in 0..<8 {
        let point = CGPoint(
          x: size.width * MIRAWallBackgroundNoise.unit(materialSeed, 180 + index * 2),
          y: size.height * MIRAWallBackgroundNoise.unit(materialSeed, 181 + index * 2)
        )
        context.fill(
          Path(ellipseIn: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)),
          with: .color(Color.black.opacity(0.055))
        )
      }
    }
    .overlay {
      LinearGradient(
        colors: [Color.white.opacity(0.11), .clear, Color.black.opacity(0.035)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .allowsHitTesting(false)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
private struct MIRACreateWallNoteView: View {
  let camera: MIRAWallCamera
  let api: MIRAAPIClient
  let onPublish: (MIRACreateWallNoteBody) async throws -> MIRAWallNote

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var voiceRecorder = MIRAWallVoiceRecorder()
  @ObservedObject private var voicePlayback = MIRAWallVoicePlaybackController.shared
  @State private var bodyText = ""
  @State private var composerMode = "text"
  @State private var identity = "ghost"
  @State private var colorToken = "butter"
  @State private var styleToken = "sticky"
  @State private var hasBackSide = false
  @State private var backBodyText = ""
  @State private var allowContributions = false
  @State private var showsAdvancedOptions = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var selectedPhotoMedia: MIRAPickedMedia?
  @State private var selectedPhotoImage: UIImage?
  @State private var uploadedPhotoResult: MIRAMediaUploadResult?
  @State private var uploadedVoiceResult: MIRAMediaUploadResult?
  @State private var isLoadingPhoto = false
  @State private var isPublishing = false
  @State private var publishStatus = ""
  @State private var errorMessage: String?
  @FocusState private var isTextFocused: Bool

  private let composerModes: [(String, String, String)] = [
    ("text", "Text", "note.text"),
    ("photo", "Photo", "photo"),
    ("voice", "Voice", "waveform"),
  ]

  private let colors = ["butter", "cream", "rose", "sky", "mint", "peach", "paper"]
  private let styles: [(String, String)] = [
    ("sticky", "Sticky"), ("editorial", "Editorial"), ("handwritten", "Handwritten"),
    ("poster", "Poster"), ("polaroid", "Photo print"), ("receipt", "Receipt"),
    ("torn_paper", "Torn"), ("notebook", "Notebook"), ("postcard", "Postcard"),
    ("minimal", "Minimal"),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          livePreview

          settingSection(title: "NOTE TYPE") {
            HStack(spacing: 8) {
              ForEach(composerModes, id: \.0) { mode in
                Button {
                  selectComposerMode(mode.0)
                } label: {
                  Label(mode.1, systemImage: mode.2)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(composerMode == mode.0 ? Color.white : MIRATheme.Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                      composerMode == mode.0 ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft,
                      in: Capsule()
                    )
                }
                .buttonStyle(.plain)
              }
            }
          }

          if composerMode == "photo" {
            settingSection(title: "PHOTO") {
              HStack(spacing: 10) {
              PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                preferredItemEncoding: .current
              ) {
                HStack(spacing: 10) {
                  if isLoadingPhoto {
                    ProgressView()
                      .tint(MIRATheme.Color.forest)
                  } else {
                    Image(systemName: selectedPhotoImage == nil ? "photo.badge.plus" : "photo.on.rectangle.angled")
                      .font(.system(size: 18, weight: .semibold))
                  }
                  Text(selectedPhotoImage == nil ? "Add a photo" : "Replace photo")
                    .font(.system(size: 14, weight: .bold))
                  Spacer()
                }
                .foregroundStyle(MIRATheme.Color.forest)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              }
              .disabled(isLoadingPhoto || isPublishing)
              .buttonStyle(.plain)

              if selectedPhotoImage != nil {
                Button {
                  removeSelectedPhoto()
                } label: {
                  Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MIRATheme.Color.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(MIRATheme.Color.surfaceSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isPublishing)
                .accessibilityLabel("Remove photo")
              }
              }

              Text(selectedPhotoImage == nil
                ? "Choose one photo, then pair it with any Captro paper style."
                : "Your photo and caption will use the paper style you choose below.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MIRATheme.Color.textSecondary)
            }
          }

          if composerMode == "voice" {
            settingSection(title: "VOICE NOTE") {
              voiceRecordingControls
            }
          }

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
                Text(notePlaceholder)
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

          HStack(spacing: 10) {
            Menu {
              Section("Paper color") {
                ForEach(colors, id: \.self) { token in
                  Button {
                    colorToken = token
                  } label: {
                    Label(colorTitle(token), systemImage: colorToken == token ? "checkmark.circle.fill" : "circle.fill")
                  }
                }
              }
              Section("Note style") {
                ForEach(styles, id: \.0) { item in
                  Button {
                    styleToken = item.0
                  } label: {
                    if styleToken == item.0 {
                      Label(item.1, systemImage: "checkmark")
                    } else {
                      Text(item.1)
                    }
                  }
                }
              }
            } label: {
              composerMenuLabel(
                title: "Appearance",
                detail: currentStyleTitle,
                icon: "paintpalette.fill",
                swatch: MIRAWallPaperColor.color(for: colorToken)
              )
            }

            Menu {
              Button {
                identity = "ghost"
              } label: {
                Label("Ghost", systemImage: identity == "ghost" ? "checkmark" : "theatermask.and.paintbrush")
              }
              Button {
                identity = "author"
              } label: {
                Label("Author", systemImage: identity == "author" ? "checkmark" : "person.crop.circle")
              }
            } label: {
              composerMenuLabel(
                title: "Identity",
                detail: identity == "author" ? "Author" : "Ghost",
                icon: identity == "author" ? "person.crop.circle" : "theatermask.and.paintbrush"
              )
            }
          }

          DisclosureGroup(isExpanded: $showsAdvancedOptions) {
            VStack(alignment: .leading, spacing: 18) {
              if composerMode != "voice" {
                Toggle("Add a back side", isOn: $hasBackSide)
                  .font(.system(size: 14, weight: .semibold))
                  .tint(MIRATheme.Color.forest)

                if hasBackSide {
                  ZStack(alignment: .topLeading) {
                    if cleanBackBody.isEmpty {
                      Text("Write what is hidden on the back...")
                        .foregroundStyle(MIRATheme.Color.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                    }
                    TextEditor(text: $backBodyText)
                      .focused($isTextFocused)
                      .scrollContentBackground(.hidden)
                      .frame(minHeight: 94)
                      .onChange(of: backBodyText) { _, value in
                        if value.count > 300 { backBodyText = String(value.prefix(300)) }
                      }
                  }
                  .padding(12)
                  .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                  .transition(.opacity.combined(with: .move(edge: .top)))
                }
              }

              Toggle("Allow contributions", isOn: $allowContributions)
                .font(.system(size: 14, weight: .semibold))
                .tint(MIRATheme.Color.forest)
            }
            .padding(.top, 14)
          } label: {
            Label("More options", systemImage: "slider.horizontal.3")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
          }
          .padding(14)
          .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
              Text(isPublishing ? (publishStatus.isEmpty ? "Placing..." : publishStatus) : "Place on Wall")
                .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(MIRATheme.Color.forest, in: Capsule())
          }
          .buttonStyle(.miraPress)
          .disabled(!canPublish || isPublishing || isLoadingPhoto)
          .opacity(canPublish ? 1 : 0.45)
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
            .disabled(isPublishing)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { isTextFocused = false }
        }
      }
      .onChange(of: selectedPhotoItem) { _, item in
        guard let item else { return }
        Task { await loadSelectedPhoto(item) }
      }
      .onDisappear {
        voicePlayback.stop()
        if !isPublishing { voiceRecorder.cancel(removeFile: true) }
      }
    }
    .interactiveDismissDisabled(isPublishing)
  }

  @ViewBuilder
  private var voiceRecordingControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: voiceStateIcon)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(width: 42, height: 42)
          .background(MIRATheme.Color.surfaceSoft, in: Circle())

        MIRAWallWaveformView(
          samples: voiceRecorder.waveform,
          progress: voicePreviewProgress,
          tint: MIRATheme.Color.forest
        )
        .frame(height: 34)

        Text(formatDuration(voiceRecorder.duration))
          .font(.system(size: 12, weight: .bold, design: .monospaced))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(minWidth: 38, alignment: .trailing)
      }

      HStack(spacing: 8) {
        switch voiceRecorder.state {
        case .idle, .denied, .failed:
          voiceControlButton("Record", icon: "mic.fill") {
            uploadedVoiceResult = nil
            Task { await voiceRecorder.start() }
          }
        case .recording:
          voiceControlButton("Pause", icon: "pause.fill") { voiceRecorder.pause() }
          voiceControlButton("Finish", icon: "checkmark") { voiceRecorder.finish() }
          voiceControlButton("Cancel", icon: "xmark", destructive: true) {
            uploadedVoiceResult = nil
            voiceRecorder.cancel()
          }
        case .paused:
          voiceControlButton("Resume", icon: "mic.fill") { voiceRecorder.resume() }
          voiceControlButton("Finish", icon: "checkmark") { voiceRecorder.finish() }
          voiceControlButton("Cancel", icon: "xmark", destructive: true) {
            uploadedVoiceResult = nil
            voiceRecorder.cancel()
          }
        case .ready:
          voiceControlButton(voicePreviewIsPlaying ? "Pause" : "Preview", icon: voicePreviewIsPlaying ? "pause.fill" : "play.fill") {
            guard let url = voiceRecorder.previewURL() else { return }
            voicePlayback.toggle(id: "wall-composer-preview", url: url)
          }
          voiceControlButton("Re-record", icon: "arrow.counterclockwise") {
            uploadedVoiceResult = nil
            voicePlayback.stop()
            voiceRecorder.cancel()
            Task { await voiceRecorder.start() }
          }
        }
      }

      Text(voiceStateMessage)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(voiceStateIsError ? Color.red : MIRATheme.Color.textSecondary)

      if case .denied = voiceRecorder.state {
        Button("Open Settings") {
          guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(settingsURL)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(minHeight: 44)
        .accessibilityHint("Opens Captro settings so microphone access can be enabled.")
      }
    }
    .padding(14)
    .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var livePreview: some View {
    let hasPhoto = composerMode == "photo" && selectedPhotoImage != nil
    let hasVoice = composerMode == "voice"
    let previewStyleToken = hasVoice ? "receipt" : styleToken
    let previewText = cleanBody.isEmpty
      ? (hasPhoto ? "Add a thought below your photo." : (hasVoice ? "Something I needed to say." : "What do you want to leave on the wall?"))
      : cleanBody
    let baseSize = MIRAWallNotePresentationResolver.recommendedSize(
      styleToken: previewStyleToken,
      text: previewText,
      hasMedia: hasPhoto
    )
    var preview = MIRAWallNote(
      id: "preview-\(previewStyleToken)", wallId: MIRAWallDestination.global.id, publishingIdentity: identity,
      body: previewText,
      category: nil, colorToken: colorToken, styleToken: previewStyleToken,
      mediaUrl: nil, mediaThumbnailUrl: nil,
      worldX: 0, worldY: 0, width: baseSize.width, height: baseSize.height,
      rotation: 0, zIndex: 0, approximateLocation: nil, createdAt: "", updatedAt: nil,
      saveCount: 0, reactionCount: 0, replyCount: 0, reactedByViewer: false, savedByViewer: false, authorPreview: nil
    )
    preview.noteType = hasVoice ? "voice" : (hasPhoto ? "photo" : "text")
    preview.hasBackSide = hasBackSide && !cleanBackBody.isEmpty
    preview.backBody = preview.hasBackSide == true ? cleanBackBody : nil
    preview.backColorToken = preview.hasBackSide == true ? colorToken : nil
    preview.backStyleToken = preview.hasBackSide == true ? previewStyleToken : nil
    preview.allowContributions = allowContributions
    if hasVoice {
      preview.voice = MIRAWallVoiceMetadata(
        mediaId: "preview-voice",
        url: voiceRecorder.previewURL()?.absoluteString,
        durationSeconds: max(voiceRecorder.duration, 0.25),
        waveform: voiceRecorder.waveform
      )
    }
    let renderedSize = MIRAWallNotePresentationResolver.resolve(preview, hasLocalMedia: hasPhoto).size
    let previewScale = min(1.08, min(258 / renderedSize.width, 286 / renderedSize.height))
    return MIRAWallNoteRenderer(
      note: preview,
      zoom: 1,
      isFocused: true,
      localMediaImage: selectedPhotoImage
    )
      .frame(width: renderedSize.width, height: renderedSize.height)
      .scaleEffect(previewScale)
      .frame(width: renderedSize.width * previewScale, height: renderedSize.height * previewScale)
      .opacity(cleanBody.isEmpty ? 0.72 : 1)
      .animation(CaptroMotion.smallMenuAnimation(reduceMotion: reduceMotion), value: previewStyleToken)
      .animation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion), value: hasPhoto)
      .padding(.vertical, 8)
  }

  private var cleanBody: String { bodyText.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var cleanBackBody: String { backBodyText.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var currentStyleTitle: String {
    styles.first(where: { $0.0 == styleToken })?.1 ?? "Style"
  }

  private func colorTitle(_ token: String) -> String {
    token.replacingOccurrences(of: "_", with: " ").capitalized
  }
  private var notePlaceholder: String {
    switch composerMode {
    case "photo": "Add a caption for your photo..."
    case "voice": "Add a short written context (optional)..."
    default: "Write your note..."
    }
  }

  private var canPublish: Bool {
    if hasBackSide && cleanBackBody.isEmpty { return false }
    switch composerMode {
    case "voice":
      if case .ready = voiceRecorder.state { return true }
      return false
    case "photo":
      return selectedPhotoMedia != nil && !cleanBody.isEmpty
    default:
      return !cleanBody.isEmpty
    }
  }

  private var voicePreviewIsPlaying: Bool {
    voicePlayback.activeID == "wall-composer-preview" && voicePlayback.isPlaying
  }

  private var voicePreviewProgress: Double {
    voicePlayback.activeID == "wall-composer-preview" ? voicePlayback.progress : 0
  }

  private var voiceStateIcon: String {
    switch voiceRecorder.state {
    case .recording: "waveform.badge.mic"
    case .paused: "pause.circle.fill"
    case .ready: "checkmark.circle.fill"
    case .denied, .failed: "exclamationmark.triangle.fill"
    case .idle: "mic.fill"
    }
  }

  private var voiceStateMessage: String {
    switch voiceRecorder.state {
    case .idle: "Record up to 60 seconds. You can preview before releasing it."
    case .recording: "Recording..."
    case .paused: "Recording paused. Resume or finish when ready."
    case .ready: "Ready to preview or release."
    case .denied: "Microphone access is off. Enable it in Settings to record a voice note."
    case .failed(let message): message
    }
  }

  private var voiceStateIsError: Bool {
    if case .denied = voiceRecorder.state { return true }
    if case .failed = voiceRecorder.state { return true }
    return false
  }

  private func voiceControlButton(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(destructive ? Color.red : MIRATheme.Color.textPrimary)
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(MIRATheme.Color.surface, in: Capsule())
    }
    .buttonStyle(.miraPress)
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  private func selectComposerMode(_ mode: String) {
    guard composerMode != mode, !isPublishing else { return }
    voicePlayback.stop()
    if mode == "voice" {
      removeSelectedPhoto()
      hasBackSide = false
      backBodyText = ""
      styleToken = "receipt"
    } else if composerMode == "voice" {
      uploadedVoiceResult = nil
      voiceRecorder.cancel()
      if styleToken == "receipt" { styleToken = "sticky" }
    }
    composerMode = mode
  }

  private func settingSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func composerMenuLabel(
    title: String,
    detail: String,
    icon: String,
    swatch: Color? = nil
  ) -> some View {
    HStack(spacing: 10) {
      if let swatch {
        Circle()
          .fill(swatch)
          .frame(width: 25, height: 25)
          .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 1))
      } else {
        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 25)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 12, weight: .bold))
        Text(detail)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 2)
      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .padding(.horizontal, 13)
    .frame(maxWidth: .infinity, minHeight: 52)
    .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
  }

  @MainActor
  private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
    isLoadingPhoto = true
    errorMessage = nil
    defer { isLoadingPhoto = false }

    do {
      guard let data = try await item.loadTransferable(type: Data.self),
            let image = await MIRAImageDiskCache.decode(data, maxPixelSize: 1_280)
      else {
        throw MIRAAPIError.server(status: 400, code: "PHOTO_READ_FAILED", detail: "Could not read this photo.")
      }

      let contentType = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
      let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
      let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"
      selectedPhotoMedia = MIRAPickedMedia(
        data: data,
        kind: .image,
        fileName: "wall-note-\(UUID().uuidString).\(fileExtension)",
        mimeType: mimeType
      )
      selectedPhotoImage = image
      uploadedPhotoResult = nil
      composerMode = "photo"
    } catch {
      selectedPhotoItem = nil
      selectedPhotoMedia = nil
      selectedPhotoImage = nil
      uploadedPhotoResult = nil
      if styleToken == MIRAWallNoteVisualStyle.polaroid.rawValue {
        styleToken = MIRAWallNoteVisualStyle.sticky.rawValue
      }
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func removeSelectedPhoto() {
    selectedPhotoItem = nil
    selectedPhotoMedia = nil
    selectedPhotoImage = nil
    uploadedPhotoResult = nil
    if styleToken == MIRAWallNoteVisualStyle.polaroid.rawValue {
      styleToken = MIRAWallNoteVisualStyle.sticky.rawValue
    }
    errorMessage = nil
  }

  private func publish() {
    let text = cleanBody
    guard canPublish, !isPublishing, !isLoadingPhoto else { return }

    let selectedMode = composerMode
    let selectedPhoto = selectedMode == "photo" ? selectedPhotoMedia : nil
    let existingPhotoUpload = selectedMode == "photo" ? uploadedPhotoResult : nil
    let existingVoiceUpload = selectedMode == "voice" ? uploadedVoiceResult : nil
    let selectedIdentity = identity
    let selectedColor = colorToken
    let selectedStyle = selectedMode == "voice" ? "receipt" : styleToken
    let selectedBackBody = hasBackSide && selectedMode != "voice" ? cleanBackBody : ""
    let selectedAllowContributions = allowContributions

    isPublishing = true
    publishStatus = selectedMode == "voice" ? "Uploading voice..." : (selectedPhoto == nil ? "Placing..." : "Checking photo...")
    errorMessage = nil

    Task {
      do {
        var photoResult = existingPhotoUpload
        if photoResult == nil, let selectedPhoto {
          let approvedUpload = try await MIRAMediaUploadService(api: api).uploadResult(selectedPhoto)
          photoResult = approvedUpload
          await MainActor.run {
            uploadedPhotoResult = approvedUpload
            publishStatus = "Placing..."
          }
        }

        var voiceResult = existingVoiceUpload
        if selectedMode == "voice", voiceResult == nil {
          let data = try voiceRecorder.recordedData()
          let uploaded = try await MIRAMediaUploadService(api: api).uploadAudioResult(
            data: data,
            fileName: "wall-voice-\(UUID().uuidString).m4a"
          )
          voiceResult = uploaded
          await MainActor.run {
            uploadedVoiceResult = uploaded
            publishStatus = "Placing..."
          }
        }

        let hasPhoto = photoResult != nil
        let noteSize = MIRAWallNotePresentationResolver.recommendedSize(
          styleToken: selectedStyle,
          text: text.isEmpty ? "Voice note" : text,
          hasMedia: hasPhoto
        )
        let noteWidth = Double(noteSize.width)
        let noteHeight = Double(noteSize.height)
        let request = MIRACreateWallNoteBody(
          wallId: MIRAWallDestination.global.id,
          publishingIdentity: selectedIdentity,
          body: text,
          category: nil,
          colorToken: selectedColor,
          styleToken: selectedStyle,
          mediaAssetId: photoResult?.mediaAssetId,
          mediaUrl: photoResult?.url,
          worldX: Double(camera.center.x) - noteWidth * 0.5,
          worldY: Double(camera.center.y) - noteHeight * 0.5,
          width: noteWidth,
          height: noteHeight,
          rotation: 0,
          approximateLocation: nil,
          noteType: selectedMode,
          backBody: selectedBackBody.isEmpty ? nil : selectedBackBody,
          backColorToken: selectedBackBody.isEmpty ? nil : selectedColor,
          backStyleToken: selectedBackBody.isEmpty ? nil : selectedStyle,
          allowContributions: selectedAllowContributions,
          voiceMediaId: voiceResult?.mediaAssetId,
          voiceDurationSeconds: selectedMode == "voice" ? voiceRecorder.duration : nil,
          voiceWaveform: selectedMode == "voice" ? voiceRecorder.waveform : nil,
          location: nil
        )
        _ = try await onPublish(request)
        await MainActor.run {
          voicePlayback.stop()
          voiceRecorder.cancel(removeFile: true)
          dismiss()
        }
      } catch {
        await MainActor.run {
          isPublishing = false
          publishStatus = ""
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

private struct MIRAWallNoteDetailView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var note: MIRAWallNote
  @ObservedObject private var voicePlayback = MIRAWallVoicePlaybackController.shared
  let api: MIRAAPIClient
  @ObservedObject var model: MIRAWallNotesModel
  let onChanged: (MIRAWallNote) -> Void
  let onClose: () -> Void

  @State private var contributions: [MIRAWallContribution] = []
  @State private var signers: [MIRAWallSigner] = []
  @State private var replyText = ""
  @State private var replyAsGhost = false
  @State private var isLoadingContributions = false
  @State private var isLoadingSigners = false
  @State private var contributionsNextAfter: String?
  @State private var signersNextBefore: String?
  @State private var isMutating = false
  @State private var errorMessage: String?
  @State private var reportTarget: MIRAReportTarget?
  @State private var showSigners = false
  @State private var showSignatureCapture = false
  @State private var showSignatureRemoval = false
  @State private var signatureError: String?
  @State private var displaysBackSide = false
  @State private var flipAngle: Double = 0
  @State private var isFlipping = false
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
      ZStack {
        MIRAWallDetailBackdrop(seed: note.id)

        VStack(spacing: 0) {
          detailHeader

          ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
              noteStage
              noteMetadataPanel

              if note.capabilities.hasVoice {
                voicePlaybackPanel
              }

              actionRow

              if let errorMessage {
                Text(errorMessage)
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(Color.red)
                  .padding(.horizontal, 12)
                  .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                  .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              }

              if note.capabilities.canManageCollaboration || note.allowContributions == true || !contributions.isEmpty {
                collaborationSection
              }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 22)
          }
          .scrollDismissesKeyboard(.interactively)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { replyFocused = false }
        }
      }
      .task { await loadContributions(reset: true) }
      .onDisappear { voicePlayback.stop() }
      .sheet(item: $reportTarget) { target in
        MIRAReportSheet(
          target: target,
          api: api,
          onSubmitted: { _ in reportTarget = nil },
          onClose: { reportTarget = nil }
        )
        .presentationDetents([.large])
      }
      .sheet(isPresented: $showSigners) {
        signersSheet
          .presentationDetents([.medium, .large])
          .presentationCornerRadius(28)
      }
      .sheet(isPresented: $showSignatureCapture) {
        MIRAWallSignatureCaptureView(
          isSaving: isMutating,
          errorMessage: signatureError,
          onCancel: { showSignatureCapture = false },
          onSubmit: submitSignature
        )
        .presentationDetents([.height(520)])
        .presentationCornerRadius(28)
        .interactiveDismissDisabled(isMutating)
      }
      .confirmationDialog(
        "Remove your signature?",
        isPresented: $showSignatureRemoval,
        titleVisibility: .visible
      ) {
        Button("Remove signature", role: .destructive, action: removeSignature)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You can draw a new signature later.")
      }
    }
    .frame(maxWidth: 420, maxHeight: 760)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 30, style: .continuous)
        .stroke(Color.white.opacity(0.56), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
  }

  private var detailVisualSize: CGSize {
    let source = MIRAWallNotePresentationResolver.resolve(note).size
    let screenWidth = UIScreen.main.bounds.width
    let maxWidth = max(190, min(300, screenWidth - 104))
    let maxHeight: CGFloat = 350
    let scale = min(maxWidth / source.width, maxHeight / source.height, 1.22)
    return CGSize(width: source.width * scale, height: source.height * scale)
  }

  private var detailRotation: Double {
    let presentation = MIRAWallNotePresentationResolver.resolve(note)
    return (note.rotation + presentation.microRotation) * 0.10
  }

  private var displayedNote: MIRAWallNote {
    displaysBackSide ? note.displayingBackSide() : note
  }

  private var noteStage: some View {
    VStack(spacing: 12) {
      flippableNote

      if note.canFlip {
        Button(action: flipNote) {
          Label(
            displaysBackSide ? "Show front" : "Turn note over",
            systemImage: "arrow.triangle.2.circlepath"
          )
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .padding(.horizontal, 14)
          .frame(minHeight: 38)
          .background(MIRATheme.Color.surface.opacity(0.92), in: Capsule())
          .overlay(Capsule().stroke(MIRATheme.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.miraPress)
        .disabled(isFlipping)
        .accessibilityLabel(displaysBackSide ? "Show the front of this note" : "Show the back of this note")
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 20)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity)
    .background(MIRAWallDetailNoteStage(seed: note.id))
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
    }
  }

  private var flippableNote: some View {
    ZStack {
      MIRAWallNoteRenderer(note: displayedNote, zoom: 1.06, isFocused: true, wallScale: 1)
        .frame(width: detailVisualSize.width, height: detailVisualSize.height)
        .rotationEffect(.degrees(detailRotation))
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
        .contentShape(Rectangle())
        .onTapGesture {
          guard note.canFlip else { return }
          flipNote()
        }
        .accessibilityHint(note.canFlip ? "Tap to show the other side." : "")
    }
    .frame(maxWidth: .infinity)
    .frame(height: detailVisualSize.height + 24)
  }

  private var voicePlaybackPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Button {
          guard let url = resolvedVoiceURL else {
            errorMessage = "This voice note is unavailable."
            return
          }
          voicePlayback.toggle(id: note.id, url: url)
        } label: {
          Image(systemName: voiceIsPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(MIRATheme.Color.forest, in: Circle())
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel(voiceIsPlaying ? "Pause voice note" : "Play voice note")

        VStack(alignment: .leading, spacing: 6) {
          MIRAWallWaveformView(
            samples: note.voice?.waveform ?? [],
            progress: voicePlayback.activeID == note.id ? voicePlayback.progress : 0,
            tint: MIRATheme.Color.forest
          )
          .frame(height: 30)
          HStack {
            Text(formatDuration(voicePlayback.activeID == note.id ? voicePlayback.elapsed : 0))
            Spacer()
            Text(formatDuration(note.voice?.durationSeconds ?? 0))
          }
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      }

      if voicePlayback.activeID == note.id, let playbackError = voicePlayback.errorMessage {
        Text(playbackError)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.red)
          .accessibilityLabel("Voice note error. \(playbackError)")
      }
    }
    .padding(14)
    .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var noteMetadataPanel: some View {
    VStack(spacing: 0) {
      authorMetadata
        .padding(.horizontal, 14)
        .padding(.vertical, 12)

      if note.resolvedSignatureCount > 0 {
        metadataDivider
        signatureSummary
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
      }
    }
    .background(MIRAWallPaperColor.color(for: "cream").opacity(0.97), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(alignment: .top) {
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(Color(red: 0.84, green: 0.75, blue: 0.57).opacity(0.68))
        .frame(width: 58, height: 12)
        .rotationEffect(.degrees(-1.4))
        .offset(y: -6)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .allowsHitTesting(false)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
    }
    .shadow(color: .black.opacity(0.08), radius: 7, x: 2, y: 5)
  }

  private var metadataDivider: some View {
    Rectangle()
      .fill(Color.black.opacity(0.07))
      .frame(height: 0.7)
      .padding(.horizontal, 14)
  }

  private var signatureSummary: some View {
    Button {
      guard note.resolvedSignatureCount > 0 else { return }
      Task { await openSigners() }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "pencil.line")
        Text(note.resolvedSignatureCount == 1 ? "Signed by 1 person" : "Signed by \(note.resolvedSignatureCount) people")
          .font(.system(size: 13, weight: .bold, design: .serif))
        Spacer()
        if note.resolvedSignatureCount > 0 {
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
        }
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(minHeight: 34)
    }
    .buttonStyle(.miraPress)
    .disabled(note.resolvedSignatureCount == 0)
  }

  private var detailHeader: some View {
    HStack(spacing: 12) {
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
          .background(MIRATheme.Color.surfaceSoft, in: Circle())
      }
      .buttonStyle(.miraPress)
      .accessibilityLabel("Close note")

      Spacer()

      Text("Note")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textPrimary)

      Spacer()

      Menu {
        Button("Report", systemImage: "exclamationmark.triangle") {
          reportTarget = MIRAReportTarget(
            targetType: "wall_note",
            targetId: note.id,
            ownerUserId: note.authorPreview?.userId,
            title: "Wall note",
            subtitle: String(note.body.prefix(90))
          )
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
          .background(MIRATheme.Color.surfaceSoft, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Note options")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(MIRATheme.Color.surface.opacity(0.88))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 0.7)
    }
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
    relativeTime(note.createdAt)
  }

  private var actionRow: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
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
      }

      HStack(spacing: 8) {
        if note.capabilities.canSign {
          detailAction(
            title: note.signedByViewer == true ? "Signed" : "Sign this note",
            count: note.resolvedSignatureCount,
            icon: note.signedByViewer == true ? "pencil.line" : "pencil",
            tint: note.signedByViewer == true ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary
          ) {
            if note.signedByViewer == true {
              showSignatureRemoval = true
            } else {
              signatureError = nil
              showSignatureCapture = true
            }
          }
        }
        ShareLink(item: URL(string: "https://captro.app/wall/notes/\(note.id)")!) {
          HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 18, weight: .semibold))
              .frame(width: 24)
            Text("Share")
              .font(.system(size: 13, weight: .bold))
            Spacer(minLength: 0)
          }
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .padding(.horizontal, 13)
          .frame(maxWidth: .infinity, minHeight: 50)
          .background(MIRATheme.Color.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
              .stroke(MIRATheme.Color.hairline, lineWidth: 1)
          }
        }
      }
    }
    .disabled(isMutating)
  }

  private func detailAction(title: String, count: Int, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 24)
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Spacer(minLength: 0)
        if count > 0 {
          Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      }
      .foregroundStyle(tint)
      .padding(.horizontal, 13)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(MIRATheme.Color.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(MIRATheme.Color.hairline, lineWidth: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.miraPress)
  }

  private var collaborationSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("CONTRIBUTIONS")
          .font(.system(size: 13, weight: .black, design: .serif))
          .tracking(0.8)
        Spacer()
        if note.resolvedContributionCount > 0 {
          Text("\(note.resolvedContributionCount)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      }

      collaborationControls
      contributionComposer
      contributionsSection
    }
    .padding(14)
    .background(MIRATheme.Color.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
    }
  }

  @ViewBuilder
  private var collaborationControls: some View {
    if note.capabilities.canManageCollaboration {
      Toggle("Allow contributions", isOn: Binding(
        get: { note.allowContributions == true },
        set: { updateCollaboration($0) }
      ))
      .font(.system(size: 14, weight: .bold, design: .serif))
      .tint(MIRATheme.Color.forest)
      .disabled(isMutating)
      .padding(12)
      .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
  }

  @ViewBuilder
  private var contributionComposer: some View {
    if note.allowContributions == true {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("Add to this note")
            .font(.system(size: 17, weight: .bold, design: .serif))
          Spacer()
          Toggle("Ghost", isOn: $replyAsGhost)
            .labelsHidden()
            .tint(MIRATheme.Color.forest)
          Text(replyAsGhost ? "Ghost" : "Author")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        HStack(alignment: .bottom, spacing: 9) {
          TextField("Attach a thoughtful response", text: $replyText, axis: .vertical)
            .focused($replyFocused)
            .lineLimit(1...4)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(MIRAWallPaperColor.color(for: "cream"), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .top) {
              RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 0.78, green: 0.68, blue: 0.48).opacity(0.65))
                .frame(width: 42, height: 11)
                .rotationEffect(.degrees(-2))
                .offset(y: -5)
            }
            .onChange(of: replyText) { _, value in
              if value.count > 300 { replyText = String(value.prefix(300)) }
            }
          Button { sendContribution() } label: {
            Image(systemName: "paperclip")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 42, height: 42)
              .background(MIRATheme.Color.forest, in: Circle())
          }
          .buttonStyle(.miraPress)
          .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isMutating)
          .accessibilityLabel("Attach contribution")
        }
      }
    } else if note.resolvedContributionCount == 0 {
      Text("This note is not accepting contributions.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var contributionsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isLoadingContributions && contributions.isEmpty {
        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 18)
      } else if !contributions.isEmpty {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 13) {
          ForEach(Array(contributions.enumerated()), id: \.element.id) { index, contribution in
            MIRAWallContributionPaper(contribution: contribution, index: index)
              .contextMenu {
                Button("Report", systemImage: "exclamationmark.triangle") {
                  reportTarget = MIRAReportTarget(
                    targetType: "wall_note_contribution",
                    targetId: contribution.id,
                    ownerUserId: contribution.authorPreview?.userId,
                    title: "Wall note contribution",
                    subtitle: String(contribution.body.prefix(90))
                  )
                }
              }
          }
        }
        if contributionsNextAfter != nil {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .task { await loadContributions(reset: false) }
            .accessibilityLabel("Loading more contributions")
        }
      }
    }
  }

  private func toggleReaction() {
    guard !isMutating else { return }
    isMutating = true
    let original = note
    let requested = !original.reactedByViewer
    let optimistic = original.updating(
      reacted: requested,
      reactionCount: max(0, original.reactionCount + (requested ? 1 : -1))
    )
    note = optimistic
    onChanged(optimistic)
    Task {
      do {
        let updated = try await model.setReaction(note: original, reacted: requested)
        await MainActor.run { note = updated; onChanged(updated); isMutating = false }
      } catch {
        await MainActor.run {
          note = original
          onChanged(original)
          errorMessage = error.localizedDescription
          isMutating = false
        }
      }
    }
  }

  private func toggleSaved() {
    guard !isMutating else { return }
    isMutating = true
    let original = note
    let requested = !original.savedByViewer
    let optimistic = original.updating(
      saved: requested,
      saveCount: max(0, original.saveCount + (requested ? 1 : -1))
    )
    note = optimistic
    onChanged(optimistic)
    Task {
      do {
        let updated = try await model.setSaved(note: original, saved: requested)
        await MainActor.run { note = updated; onChanged(updated); isMutating = false }
      } catch {
        await MainActor.run {
          note = original
          onChanged(original)
          errorMessage = error.localizedDescription
          isMutating = false
        }
      }
    }
  }

  private func submitSignature(_ drawing: MIRAWallSignatureDrawing) {
    guard !isMutating, note.capabilities.canSign, !drawing.isEmpty else { return }
    isMutating = true
    let original = note
    let optimistic = original.updating(
      signed: true,
      signatureCount: max(0, original.resolvedSignatureCount + (original.signedByViewer == true ? 0 : 1))
    )
    note = optimistic
    onChanged(optimistic)
    Task {
      do {
        let updated = try await model.setSigned(note: original, signed: true, drawing: drawing)
        await MainActor.run {
          note = updated
          onChanged(updated)
          signers = []
          signersNextBefore = nil
          signatureError = nil
          showSignatureCapture = false
          isMutating = false
        }
      } catch {
        await MainActor.run {
          note = original
          onChanged(original)
          signatureError = error.localizedDescription
          isMutating = false
        }
      }
    }
  }

  private func removeSignature() {
    guard !isMutating, note.capabilities.canSign, note.signedByViewer == true else { return }
    isMutating = true
    let original = note
    let optimistic = original.updating(
      signed: false,
      signatureCount: max(0, original.resolvedSignatureCount - 1)
    )
    note = optimistic
    onChanged(optimistic)
    Task {
      do {
        let updated = try await model.setSigned(note: original, signed: false)
        await MainActor.run {
          note = updated
          onChanged(updated)
          signers = []
          signersNextBefore = nil
          isMutating = false
        }
      } catch {
        await MainActor.run {
          note = original
          onChanged(original)
          errorMessage = error.localizedDescription
          isMutating = false
        }
      }
    }
  }

  private func updateCollaboration(_ allowed: Bool) {
    guard !isMutating, note.capabilities.canManageCollaboration else { return }
    isMutating = true
    let original = note
    let optimistic = original.updating(allowContributions: allowed)
    note = optimistic
    onChanged(optimistic)
    Task {
      do {
        let updated = try await model.setCollaboration(note: original, allowed: allowed)
        await MainActor.run { note = updated; onChanged(updated); isMutating = false }
      } catch {
        await MainActor.run {
          note = original
          onChanged(original)
          errorMessage = error.localizedDescription
          isMutating = false
        }
      }
    }
  }

  private func loadContributions(reset: Bool) async {
    guard !isLoadingContributions else { return }
    if !reset, contributionsNextAfter == nil { return }
    isLoadingContributions = true
    defer { isLoadingContributions = false }
    do {
      let response = try await model.contributions(
        for: note,
        after: reset ? nil : contributionsNextAfter
      )
      if reset {
        contributions = response.contributions
      } else {
        contributions = mergingUnique(contributions, response.contributions, id: \.id)
      }
      contributionsNextAfter = response.nextAfter
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func sendContribution() {
    let clean = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !isMutating, note.allowContributions == true else { return }
    isMutating = true
    Task {
      do {
        let contribution = try await model.addContribution(note: note, body: clean, identity: replyAsGhost ? "ghost" : "author")
        await MainActor.run {
          contributions.append(contribution)
          let count = note.resolvedContributionCount + 1
          note = note.updating(replyCount: count, contributionCount: count)
          onChanged(note)
          replyText = ""
          isMutating = false
        }
      } catch {
        await MainActor.run { errorMessage = error.localizedDescription; isMutating = false }
      }
    }
  }

  private func openSigners() async {
    showSigners = true
    guard signers.isEmpty, !isLoadingSigners else { return }
    await loadSigners(reset: true)
  }

  private func loadSigners(reset: Bool) async {
    guard !isLoadingSigners else { return }
    if !reset, signersNextBefore == nil { return }
    isLoadingSigners = true
    defer { isLoadingSigners = false }
    do {
      var cursor = reset ? nil : signersNextBefore
      var pageSigners: [MIRAWallSigner] = []
      var nextCursor: String?

      // A server page can contain only blocked or inactive accounts. Advance a
      // few bounded pages so the sheet never gets stranded on an empty result.
      for _ in 0..<4 {
        let response = try await model.signers(for: note, before: cursor)
        pageSigners = mergingUnique(pageSigners, response.signers, id: \.id)
        nextCursor = response.nextBefore
        guard pageSigners.isEmpty, let next = nextCursor, next != cursor else { break }
        cursor = next
      }
      if reset {
        signers = pageSigners
      } else {
        signers = mergingUnique(signers, pageSigners, id: \.id)
      }
      signersNextBefore = nextCursor
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var signersSheet: some View {
    NavigationStack {
      Group {
        if isLoadingSigners && signers.isEmpty {
          ProgressView("Loading signatures...")
        } else if signers.isEmpty {
          ContentUnavailableView("No signatures yet", systemImage: "pencil.line")
        } else {
          List(signers) { signer in
            HStack(spacing: 12) {
              MIRAWallAvatar(url: signer.avatarUrl, size: 40)
              Text(signer.title)
                .font(.system(size: 15, weight: .semibold))
              Spacer()
              if let drawing = signer.drawing, !drawing.isEmpty {
                MIRAWallSignatureInkView(drawing: drawing, lineWidth: 1.55)
                  .frame(width: 86, height: 34)
                  .padding(.horizontal, 7)
                  .padding(.vertical, 4)
                  .background(
                    MIRAWallPaperColor.color(for: "cream"),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                  )
                  .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                      .stroke(Color.black.opacity(0.07), lineWidth: 0.7)
                  }
              }
            }
            .listRowBackground(MIRATheme.Color.surface)
            .task {
              guard signer.id == signers.last?.id, signersNextBefore != nil else { return }
              await loadSigners(reset: false)
            }
          }
          .listStyle(.plain)
          .overlay(alignment: .bottom) {
            if isLoadingSigners {
              ProgressView()
                .padding(10)
                .background(.thinMaterial, in: Capsule())
                .accessibilityLabel("Loading more signatures")
            }
          }
        }
      }
      .background(MIRATheme.Color.surface)
      .navigationTitle("Signed by")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { showSigners = false }
        }
      }
    }
  }

  private func mergingUnique<Element, ID: Hashable>(
    _ existing: [Element],
    _ incoming: [Element],
    id: KeyPath<Element, ID>
  ) -> [Element] {
    var seen = Set(existing.map { $0[keyPath: id] })
    return existing + incoming.filter { seen.insert($0[keyPath: id]).inserted }
  }

  private func flipNote() {
    guard note.canFlip, !isFlipping else { return }
    if reduceMotion {
      displaysBackSide.toggle()
      return
    }
    isFlipping = true
    withAnimation(.easeIn(duration: 0.18)) { flipAngle = 88 }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(175))
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        displaysBackSide.toggle()
        flipAngle = -88
      }
      withAnimation(.easeOut(duration: 0.20)) { flipAngle = 0 }
      try? await Task.sleep(for: .milliseconds(205))
      isFlipping = false
    }
  }

  private var resolvedVoiceURL: URL? {
    guard let raw = note.voice?.url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
    if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
    let base = api.baseURL.absoluteString.hasSuffix("/") ? api.baseURL : URL(string: api.baseURL.absoluteString + "/")!
    return URL(string: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: base)?.absoluteURL
  }

  private var voiceIsPlaying: Bool {
    voicePlayback.activeID == note.id && voicePlayback.isPlaying
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", total / 60, total % 60)
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

private struct MIRAWallContributionPaper: View {
  let contribution: MIRAWallContribution
  let index: Int

  private var paperColor: Color {
    let tokens = ["cream", "sky", "butter", "rose", "mint"]
    return MIRAWallPaperColor.color(for: tokens[index % tokens.count])
  }

  private var angle: Double {
    [-1.8, 1.2, -0.7, 1.7, -1.1][index % 5]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(contribution.body)
        .font(.system(size: 14, weight: .medium, design: index.isMultiple(of: 2) ? .serif : .rounded))
        .foregroundStyle(Color.black.opacity(0.82))
        .lineLimit(7)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: 4)

      HStack(spacing: 5) {
        Image(systemName: contribution.isGhost ? "theatermask.and.paintbrush" : "person.crop.circle")
        Text(contribution.isGhost ? "Ghost" : (contribution.authorPreview?.title ?? "Captro member"))
          .lineLimit(1)
      }
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(Color.black.opacity(0.55))
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    .background(paperColor)
    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    .overlay(alignment: .top) {
      if index.isMultiple(of: 2) {
        RoundedRectangle(cornerRadius: 1)
          .fill(Color(red: 0.80, green: 0.69, blue: 0.49).opacity(0.64))
          .frame(width: 44, height: 10)
          .rotationEffect(.degrees(index.isMultiple(of: 4) ? -3 : 2))
          .offset(y: -5)
      } else {
        Image(systemName: "paperclip")
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.44))
          .rotationEffect(.degrees(-12))
          .offset(y: -7)
      }
    }
    .rotationEffect(.degrees(angle))
    .shadow(color: .black.opacity(0.11), radius: 4, x: 1, y: 3)
    .accessibilityElement(children: .combine)
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
