import SwiftUI
import UIKit

@MainActor
final class NoteDetailNativeModel: ObservableObject {
  @Published var note: MIRANote
  @Published var comments: [MIRAComment] = []
  let api: MIRAAPIClient

  init(note: MIRANote, api: MIRAAPIClient) {
    self.note = note
    self.api = api
  }

  func load() async {
    if let fresh: MIRANote = try? await api.get("/notes/\(note.id)") {
      note = fresh
    }
    comments = (try? await api.get("/notes/\(note.id)/comments")) ?? []
  }

  func sendSignature(_ text: String) async {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    if let comment: MIRAComment = try? await api.post("/notes/\(note.id)/comments", body: NoteCommentBody(body: clean, parentId: nil)) {
      comments.append(comment)
      note = note.updating(commentsCount: (note.commentsCount ?? 0) + 1)
    }
  }

  func followAuthor() async {
    guard let userId = note.user?.id, !userId.isEmpty else { return }
    let _: FollowResponse? = try? await api.post("/users/\(userId)/follow", body: FollowBody(following: true))
  }

  func toggleReaction() async {
    let previous = note
    let nextReacted = !(note.reacted ?? false)
    let nextCount = max(0, (note.reactionsCount ?? 0) + (nextReacted ? 1 : -1))
    note = note.updating(reactionsCount: nextCount, reacted: nextReacted)
    do {
      let response: NoteInteractionResponse = try await api.post("/notes/\(note.id)/interactions", body: NoteInteractionBody(kind: "reaction", value: "heart"))
      note = note.updating(reacted: response.active ?? nextReacted)
    } catch {
      note = previous
    }
  }

  func toggleSave() async {
    let previous = note
    let nextSaved = !(note.saved ?? false)
    let nextCount = max(0, (note.savesCount ?? 0) + (nextSaved ? 1 : -1))
    note = note.updating(savesCount: nextCount, saved: nextSaved)
    do {
      let response: NoteInteractionResponse = try await api.post("/notes/\(note.id)/interactions", body: NoteInteractionBody(kind: "save", value: nil))
      note = note.updating(saved: response.active ?? nextSaved)
    } catch {
      note = previous
    }
  }

  func recordShare() async {
    let previous = note
    note = note.updating(sharesCount: (note.sharesCount ?? 0) + 1)
    do {
      let _: NoteInteractionResponse = try await api.post("/notes/\(note.id)/interactions", body: NoteInteractionBody(kind: "share", value: nil))
    } catch {
      note = previous
    }
  }

  func report(reason: String) async {
    let _: EmptyResponse? = try? await api.post("/notes/\(note.id)/report", body: NoteReportBody(reason: reason, details: nil))
  }
}

public struct NoteDetailNativeView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: NoteDetailNativeModel
  @State private var showMenu = false
  @State private var showSignSheet = false
  @State private var selectedPhoto: NotePhotoViewerItem?
  private let horizontalInset: CGFloat = MIRATheme.Space.md

  public init(note: MIRANote, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: NoteDetailNativeModel(note: note, api: api))
  }

  public var body: some View {
    GeometryReader { proxy in
      let contentWidth = max(0, proxy.size.width - horizontalInset * 2)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          topBar
            .padding(.horizontal, horizontalInset)
            .padding(.top, 8)

          artworkStage(width: contentWidth)
            .padding(.horizontal, horizontalInset)
            .padding(.top, 8)

          actionBar
            .padding(.horizontal, horizontalInset)
            .padding(.top, 14)

          creatorCaption
            .padding(.horizontal, horizontalInset)
            .padding(.top, 18)

          detailBlocks
            .padding(.horizontal, horizontalInset)
            .padding(.top, 18)

          signatures
            .padding(.horizontal, horizontalInset)
            .padding(.top, 20)
        }
        .padding(.bottom, 34)
      }
      .scrollIndicators(.hidden)
    }
    .background(viewerBackground.ignoresSafeArea())
    .miraScreenEnter(.push)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .confirmationDialog("Note options", isPresented: $showMenu) {
      Button("Copy link") {
        UIPasteboard.general.string = "\(MIRAProductionBackend.siteBaseURL.absoluteString)/note/\(model.note.id)"
      }
      Button("Not interested", role: .destructive) {}
      Button("Report", role: .destructive) {
        Task { await model.report(reason: "other") }
      }
      Button("Cancel", role: .cancel) {}
    }
    .miraBottomSheet(isPresented: $showSignSheet, preferredHeightFraction: 0.44, maxHeight: 420) { dismissSheet in
      NoteSignSheet(authorName: model.note.user?.displayName ?? model.note.user?.username ?? "Captro") { value in
        Task {
          await model.sendSignature(value)
          dismissSheet()
        }
      } onClose: {
        dismissSheet()
      }
    }
    .miraFullScreenOverlay(item: $selectedPhoto, background: .black) { item, closeViewer in
      NoteMediaViewer(photo: item.photo, onClose: closeViewer)
    }
    .task { await model.load() }
  }

  private var topBar: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44, alignment: .leading)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Back")

      Spacer()

      Button {
        showMenu = true
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44, alignment: .trailing)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("More note actions")
    }
  }

  private func artworkStage(width: CGFloat) -> some View {
    let document = model.note.displayDocument
    return NoteCanvasRenderer(document: document, mode: .detail) { photo, frame in
      selectedPhoto = NotePhotoViewerItem(photo: photo, sourceFrame: frame)
    }
    .frame(width: width)
    .shadow(color: .black.opacity(0.16), radius: 20, x: 0, y: 10)
    .accessibilityLabel(document.altText ?? document.caption ?? "Note artwork")
  }

  private var actionBar: some View {
    HStack(spacing: 10) {
      NoteCompactAction(
        title: "Feel",
        systemImage: model.note.reacted == true ? "heart.fill" : "heart",
        count: model.note.reactionsCount,
        tint: model.note.reacted == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary
      ) {
        Task { await model.toggleReaction() }
      }

      NoteCompactAction(title: "Sign", systemImage: "signature", count: model.note.commentsCount, tint: MIRATheme.Color.textSecondary) {
        showSignSheet = true
      }

      NoteCompactAction(
        title: "Save",
        systemImage: model.note.saved == true ? "bookmark.fill" : "bookmark",
        count: model.note.savesCount,
        tint: model.note.saved == true ? MIRATheme.Color.forest : MIRATheme.Color.textSecondary
      ) {
        Task { await model.toggleSave() }
      }

      ShareLink(item: shareText) {
        HStack(spacing: 5) {
          Image(systemName: "square.and.arrow.up")
          Text("Share")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
      }
      .simultaneousGesture(TapGesture().onEnded {
        Task { await model.recordShare() }
      })
    }
  }

  private var creatorCaption: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Button(action: { Task { await model.followAuthor() } }) {
          MIRAFollowAvatar(url: model.note.user?.profileImage, size: 42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Follow creator")

        VStack(alignment: .leading, spacing: 2) {
          Text(model.note.user?.displayName ?? model.note.user?.username ?? "Captro")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
          Text(noteAge(model.note.createdAt))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        Spacer()
      }

      if let caption = model.note.displayDocument.caption, !caption.isEmpty {
        Text(caption)
          .font(.system(size: 16, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var detailBlocks: some View {
    let blocks = model.note.displayDocument.detailBlocks
    if !blocks.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("Details")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        ForEach(blocks) { block in
          NoteDetailBlockView(block: block)
        }
      }
    }
  }

  private var signatures: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Signatures")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Spacer()
        Button("Sign") {
          showSignSheet = true
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
      }

      if commentsForDisplay.isEmpty {
        Text("No signatures yet.")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      } else {
        LazyVStack(spacing: 12) {
          ForEach(commentsForDisplay) { comment in
            NoteSignatureRow(comment: comment)
          }
        }
      }
    }
  }

  private var commentsForDisplay: [MIRAComment] {
    commentsSorted(model.comments)
  }

  private var viewerBackground: Color {
    switch model.note.displayDocument.canvas.background {
    case .material(.blackLeather), .material(.darkCardstock):
      return Color.miraHex("#F3F0EA")
    case .solid(let value) where value.uppercased() == "#111111":
      return Color.miraHex("#F3F0EA")
    default:
      return Color.miraHex("#FAF9F5")
    }
  }

  private var shareText: String {
    if let caption = model.note.displayDocument.caption, !caption.isEmpty {
      return "\(caption)\n\(MIRAProductionBackend.siteBaseURL.absoluteString)/note/\(model.note.id)"
    }
    return "\(MIRAProductionBackend.siteBaseURL.absoluteString)/note/\(model.note.id)"
  }
}

private struct NotePhotoViewerItem: Identifiable {
  let id = UUID().uuidString
  let photo: PhotoElement
  let sourceFrame: CGRect
}

private struct NoteCompactAction: View {
  let title: String
  let systemImage: String
  let count: Int?
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: systemImage)
        Text(title)
        if let count {
          Text("\(count)")
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(tint)
      .frame(maxWidth: .infinity)
      .frame(height: 38)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}

private struct NoteDetailBlockView: View {
  let block: NoteDetailBlock
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      content
    }
    .padding(14)
    .background(MIRATheme.Color.surfaceSoft)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var content: some View {
    switch block {
    case .text(let block):
      detailText(block.body)
      if let link = block.link { linkButton("Open link", link) }
    case .event(let block):
      detailText([block.date, block.startTime, block.endTime].compactMap { $0 }.joined(separator: " "))
      detailText([block.venue, block.address].compactMap { $0 }.joined(separator: "\n"))
      if let ticketURL = block.ticketUrl { linkButton("Tickets or RSVP", ticketURL) }
    case .recipe(let block):
      if let prep = block.prepTime { detailText("Prep: \(prep)") }
      if let cook = block.cookTime { detailText("Cook: \(cook)") }
      if let servings = block.servings { detailText("Serves: \(servings)") }
      detailText("Ingredients\n\(block.ingredients.joined(separator: "\n"))")
      detailText("Steps\n\(block.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))")
      if let sourceURL = block.sourceUrl { linkButton("Source", sourceURL) }
    case .bookReview(let block):
      if let author = block.author { detailText(author) }
      if let rating = block.rating { detailText(String(format: "Rating: %.1f", rating)) }
      detailText(block.review)
      if let quote = block.favoriteQuote { detailText("Favorite quote\n\(quote)") }
      if let link = block.link { linkButton("Book link", link) }
    case .location(let block):
      detailText([block.placeName, block.city].compactMap { $0 }.joined(separator: "\n"))
      if let mapURL = block.mapUrl { linkButton("Directions", mapURL) }
    case .link(let block):
      if let description = block.description { detailText(description) }
      linkButton("Open link", block.url)
    case .credits(let block):
      detailText([
        block.photographer.map { "Photographer: \($0)" },
        block.designer.map { "Designer: \($0)" },
        block.artist.map { "Artist: \($0)" },
        block.source.map { "Source: \($0)" },
        block.collaborators.isEmpty ? nil : "Collaborators: \(block.collaborators.joined(separator: ", "))",
      ].compactMap { $0 }.joined(separator: "\n"))
    }
  }

  private var title: String {
    switch block {
    case .text(let block): return block.heading
    case .event(let block): return block.title
    case .recipe(let block): return block.title
    case .bookReview(let block): return block.title
    case .location(let block): return block.placeName
    case .link(let block): return block.title
    case .credits: return "Credits"
    }
  }

  private var icon: String {
    switch block {
    case .text: return "text.alignleft"
    case .event: return "calendar"
    case .recipe: return "fork.knife"
    case .bookReview: return "book"
    case .location: return "mappin"
    case .link: return "link"
    case .credits: return "person.2"
    }
  }

  private func detailText(_ value: String) -> some View {
    Text(value)
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(MIRATheme.Color.textSecondary)
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func linkButton(_ label: String, _ value: String) -> some View {
    Button {
      if let url = URL(string: value) {
        openURL(url)
      }
    } label: {
      Label(label, systemImage: "arrow.up.right")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
    }
    .buttonStyle(.plain)
  }
}

private struct NoteSignSheet: View {
  let authorName: String
  let onSubmit: (String) -> Void
  let onClose: () -> Void
  @State private var draft = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack {
        Text("Sign this Note")
          .font(.system(size: 20, weight: .semibold))
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 34, height: 34)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }

      Text("Leave a short guestbook-style signature for \(authorName).")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)

      TextField("Your signature", text: $draft, axis: .vertical)
        .focused($focused)
        .lineLimit(3...5)
        .font(.system(size: 16, weight: .medium))
        .padding(14)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      Button {
        onSubmit(draft)
        draft = ""
      } label: {
        Text("Sign")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MIRATheme.Color.textMuted.opacity(0.45) : MIRATheme.Color.forest)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Spacer()
    }
    .padding(MIRATheme.Space.md)
    .onAppear { focused = true }
  }
}

private struct NoteSignatureRow: View {
  let comment: MIRAComment

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RemoteAvatar(url: comment.user?.profileImage, size: 36)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(comment.user?.displayName ?? comment.user?.username ?? "user")
            .font(.system(size: 14, weight: .semibold))
          Text(noteAge(comment.createdAt))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        Text(comment.text)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
    }
    .padding(12)
    .background(MIRATheme.Color.surfaceSoft.opacity(0.64))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private func commentsSorted(_ comments: [MIRAComment]) -> [MIRAComment] {
  comments.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
}

private func noteAge(_ value: String?) -> String {
  guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "" }
  let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  if hours < 24 { return "\(hours)h" }
  return "\(hours / 24)d"
}
