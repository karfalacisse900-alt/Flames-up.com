import SwiftUI

@MainActor
final class NotesWallNativeModel: ObservableObject {
  @Published var notes: [MIRANote] = []
  @Published var isLoading = true
  @Published var errorMessage: String?
  let api: MIRAAPIClient
  private let cacheKey = "native.notes.wall.v1"
  private var hasLoadedFreshNotes = false

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func prepareForStartup() async {
    await hydrateCache()
    Task { await load() }
  }

  func load(forceRefresh: Bool = false) async {
    if hasLoadedFreshNotes && !forceRefresh && !notes.isEmpty { return }
    await hydrateCache()
    if notes.isEmpty { isLoading = true }
    defer { isLoading = false }
    do {
      let loaded: [MIRANote] = try await api.get("/notes?limit=60")
      notes = loaded
      hasLoadedFreshNotes = true
      errorMessage = nil
      await MIRALocalJSONCache.save(loaded, key: cacheKey)
      prewarmArtwork(for: loaded)
    } catch {
      if notes.isEmpty {
        errorMessage = "Could not load Wall of Notes."
        hasLoadedFreshNotes = false
      }
    }
  }

  func toggleReaction(_ note: MIRANote) async {
    guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
    let previous = notes[index]
    let nextReacted = !(previous.reacted ?? false)
    let nextCount = max(0, (previous.reactionsCount ?? 0) + (nextReacted ? 1 : -1))
    notes[index] = previous.updating(reactionsCount: nextCount, reacted: nextReacted)
    do {
      let response: NoteInteractionResponse = try await api.post("/notes/\(note.id)/interactions", body: NoteInteractionBody(kind: "reaction", value: "heart"))
      if let current = notes.firstIndex(where: { $0.id == note.id }) {
        notes[current] = notes[current].updating(reacted: response.active ?? nextReacted)
      }
      cacheCurrentNotes()
    } catch {
      if let current = notes.firstIndex(where: { $0.id == note.id }) {
        notes[current] = previous
      }
    }
  }

  func hide(_ note: MIRANote) {
    notes.removeAll { $0.id == note.id }
    cacheCurrentNotes()
  }

  func report(_ note: MIRANote) async {
    let _: EmptyResponse? = try? await api.post("/notes/\(note.id)/report", body: NoteReportBody(reason: "other", details: "Reported from Wall of Notes."))
  }

  private func hydrateCache() async {
    guard notes.isEmpty, let cached: [MIRANote] = await MIRALocalJSONCache.load([MIRANote].self, key: cacheKey) else { return }
    notes = cached
    isLoading = false
  }

  private func cacheCurrentNotes() {
    let snapshot = notes
    Task { await MIRALocalJSONCache.save(snapshot, key: cacheKey) }
  }

  private func prewarmArtwork(for notes: [MIRANote]) {
    let urls = notes
      .flatMap { $0.displayDocument.canvas.elements }
      .compactMap { $0.photo?.url }
      .filter { !$0.isEmpty }
      .prefix(12)
    guard !urls.isEmpty else { return }
    Task.detached(priority: .utility) {
      for value in urls {
        guard let url = URL(string: value), MIRANetworkSecurityPolicy.isSecureMediaURL(url) else { continue }
        if await MIRAImageDiskCache.image(for: url, maxPixelSize: 900) != nil { continue }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 6
        if let (data, _) = try? await MIRAAPIClient.productionSession.data(for: request), data.count <= 10 * 1024 * 1024 {
          await MIRAImageDiskCache.store(data: data, for: url)
        }
      }
    }
  }
}

public struct NotesWallNativeView: View {
  @StateObject private var model: NotesWallNativeModel
  @State private var selectedFilter: NotesWallFilter = .all
  @State private var searchText = ""
  @State private var isShowingCreateNote = false

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: NotesWallNativeModel(api: api))
  }

  init(api: MIRAAPIClient, model: NotesWallNativeModel) {
    _model = StateObject(wrappedValue: model)
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        wallHeader
        GeometryReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              filterRail
              searchField

              if model.isLoading && model.notes.isEmpty {
                NotesWallSkeleton()
              } else if filteredNotes.isEmpty {
                MIRAEmptyState(title: "No notes yet", message: "Visual notes will appear here as people publish them.", systemImage: "rectangle.grid.2x2")
                  .padding(.top, 70)
              } else {
                NotesMasonryWall(
                  notes: filteredNotes,
                  width: max(1, proxy.size.width - MIRATheme.Space.md * 2),
                  api: model.api,
                  onFeel: { note in Task { await model.toggleReaction(note) } },
                  onReport: { note in Task { await model.report(note) } },
                  onHide: { note in model.hide(note) }
                )
              }
            }
            .padding(.horizontal, MIRATheme.Space.md)
            .padding(.top, MIRATheme.Space.sm)
            .padding(.bottom, MIRATheme.Space.xxl + 28)
          }
          .refreshable { await model.load(forceRefresh: true) }
        }
      }
      .background(MIRATheme.Color.appBackground)
      .toolbar(.hidden, for: .navigationBar)
      .miraScreenEnter(.tab)
      .miraFullScreenOverlay(isPresented: $isShowingCreateNote, background: MIRATheme.Color.appBackground) { dismiss in
        NoteCreationFlowView(api: model.api) {
          dismiss()
          Task { await model.load(forceRefresh: true) }
        }
      }
      .task { await model.load() }
    }
  }

  private var wallHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Text("Wall of Notes")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
      Button {
        isShowingCreateNote = true
      } label: {
        MIRAHeaderCircleButton(systemImage: "plus")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Create note")
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, 8)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var filterRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(NotesWallFilter.allCases) { filter in
          Button {
            withAnimation(.easeInOut(duration: 0.16)) {
              selectedFilter = filter
            }
          } label: {
            Text(filter.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(selectedFilter == filter ? .white : MIRATheme.Color.textPrimary)
              .padding(.horizontal, 14)
              .frame(height: 34)
              .background(selectedFilter == filter ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 9) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(MIRATheme.Color.textMuted)
      TextField("Search notes", text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(size: 15, weight: .medium))
    }
    .padding(.horizontal, 14)
    .frame(height: 42)
    .background(MIRATheme.Color.surfaceSoft)
    .clipShape(Capsule())
  }

  private var filteredNotes: [MIRANote] {
    let base = model.notes.filter { note in
      switch selectedFilter {
      case .all:
        return true
      case .friends:
        return note.visibility == .friends
      case .events:
        return note.contentKind == .event || note.displayDocument.contentKind == .event
      case .new:
        return true
      }
    }

    let searched = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !searched.isEmpty else { return base }
    return base.filter { note in
      [
        note.body,
        note.displayDocument.caption,
        note.user?.displayName,
        note.user?.username,
        note.displayDocument.contentKind?.rawValue,
      ]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")
      .contains(searched)
    }
  }
}

private enum NotesWallFilter: String, CaseIterable, Identifiable {
  case all
  case friends
  case events
  case new

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "All"
    case .friends: return "Friends"
    case .events: return "Events"
    case .new: return "New"
    }
  }
}

private struct NotesMasonryWall: View {
  let notes: [MIRANote]
  let width: CGFloat
  let api: MIRAAPIClient
  let onFeel: (MIRANote) -> Void
  let onReport: (MIRANote) -> Void
  let onHide: (MIRANote) -> Void

  var body: some View {
    VStack(spacing: 16) {
      if let featured = notes.first {
        NotesWallCard(note: featured, width: width, api: api, isFeatured: true, onFeel: onFeel)
          .contextMenu { contextMenu(for: featured) }
      }

      HStack(alignment: .top, spacing: 14) {
        LazyVStack(spacing: 18) {
          ForEach(columns.left) { note in
            NotesWallCard(note: note, width: columnWidth, api: api, isFeatured: false, onFeel: onFeel)
              .contextMenu { contextMenu(for: note) }
          }
        }

        LazyVStack(spacing: 18) {
          ForEach(columns.right) { note in
            NotesWallCard(note: note, width: columnWidth, api: api, isFeatured: false, onFeel: onFeel)
              .contextMenu { contextMenu(for: note) }
          }
        }
      }
    }
  }

  private var columnWidth: CGFloat {
    (width - 14) / 2
  }

  private var columns: (left: [MIRANote], right: [MIRANote]) {
    var left: [MIRANote] = []
    var right: [MIRANote] = []
    var leftHeight: CGFloat = 0
    var rightHeight: CGFloat = 0

    for note in notes.dropFirst() {
      let aspect = max(0.34, note.displayDocument.canvasAspectRatio)
      let estimatedHeight = columnWidth / aspect + 44
      if leftHeight <= rightHeight {
        left.append(note)
        leftHeight += estimatedHeight
      } else {
        right.append(note)
        rightHeight += estimatedHeight
      }
    }

    return (left, right)
  }

  @ViewBuilder
  private func contextMenu(for note: MIRANote) -> some View {
    Button(role: .destructive) {
      onReport(note)
    } label: {
      Label("Report", systemImage: "flag")
    }

    Button {
      onHide(note)
    } label: {
      Label("Not interested", systemImage: "eye.slash")
    }
  }
}

private struct NotesWallCard: View {
  let note: MIRANote
  let width: CGFloat
  let api: MIRAAPIClient
  let isFeatured: Bool
  let onFeel: (MIRANote) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      NavigationLink(destination: NoteDetailNativeView(note: note, api: api)) {
        NoteCanvasRenderer(document: note.displayDocument, mode: .wall)
          .frame(width: width)
          .shadow(color: shadowColor, radius: isFeatured ? 18 : 10, x: 0, y: isFeatured ? 9 : 5)
          .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(note.displayDocument.altText ?? note.displayDocument.caption ?? "Open note")

      HStack(spacing: 8) {
        Text(note.user?.displayName ?? note.user?.username ?? "Captro")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
        Spacer(minLength: 4)
        Button {
          onFeel(note)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: note.reacted == true ? "heart.fill" : "heart")
              .font(.system(size: 11, weight: .semibold))
            Text("\(note.reactionsCount ?? 0)")
              .font(.system(size: 11, weight: .semibold))
          }
          .foregroundStyle(note.reacted == true ? MIRATheme.Color.like : MIRATheme.Color.textMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feel note")
      }
      .frame(width: width)
    }
  }

  private var shadowColor: Color {
    isDarkBackground ? .black.opacity(0.22) : .black.opacity(0.12)
  }

  private var isDarkBackground: Bool {
    switch note.displayDocument.canvas.background {
    case .solid(let value):
      return value.uppercased() == "#111111"
    case .material(.blackLeather), .material(.darkCardstock):
      return true
    default:
      return false
    }
  }
}

private struct NotesWallSkeleton: View {
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(spacing: 18) {
        skeleton(height: 250)
        skeleton(height: 190)
        skeleton(height: 285)
      }
      VStack(spacing: 18) {
        skeleton(height: 210)
        skeleton(height: 310)
        skeleton(height: 220)
      }
    }
    .redacted(reason: .placeholder)
  }

  private func skeleton(height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(MIRATheme.Color.surfaceSoft)
      .frame(height: height)
  }
}
