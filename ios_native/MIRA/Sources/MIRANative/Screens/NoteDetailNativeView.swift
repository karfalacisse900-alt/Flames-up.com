import SwiftUI
import UIKit

@MainActor
final class NoteDetailNativeModel: ObservableObject {
  @Published var note: MIRANote
  @Published var comments: [MIRAComment] = []
  private let api: MIRAAPIClient

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

  func sendReply(_ text: String) async {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    if let comment: MIRAComment = try? await api.post("/notes/\(note.id)/comments", body: NoteCommentBody(body: clean, parentId: nil)) {
      comments.append(comment)
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
  @State private var draft = ""
  @State private var showMenu = false
  @FocusState private var replyFocused: Bool
  private var mediaHeight: CGFloat {
    if let media = model.note.mediaUrl, !media.isEmpty {
      let width = UIScreen.main.bounds.width - (MIRATheme.Space.md * 2)
      return min(MIRAMediaSizing.feedHeight(for: [media], width: width), UIScreen.main.bounds.height * 0.43)
    }
    return 0
  }

  public init(note: MIRANote, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: NoteDetailNativeModel(note: note, api: api))
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        topBar
        noteHeader
          .padding(.top, 18)
        noteBody
          .padding(.top, 14)
        noteActions
          .padding(.top, 16)
        Rectangle()
          .fill(MIRATheme.Color.hairline.opacity(0.62))
          .frame(height: 0.7)
          .padding(.top, 18)
        commentsList
          .padding(.top, 20)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, 8)
      .padding(.bottom, 104)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      replyBar
    }
    .background(MIRATheme.Color.surface.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .confirmationDialog("Note options", isPresented: $showMenu) {
      Button("Not interested", role: .destructive) {}
      Button("Report", role: .destructive) {
        Task { await model.report(reason: "other") }
      }
      Button("Cancel", role: .cancel) {}
    }
    .task { await model.load() }
  }

  private var topBar: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 48, height: 48, alignment: .leading)
      }
      .buttonStyle(.plain)

      Spacer()

      Button {
        showMenu = true
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 23, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 48, height: 48, alignment: .trailing)
      }
      .buttonStyle(.plain)
    }
  }

  private var noteHeader: some View {
    HStack(spacing: 12) {
      Button(action: { Task { await model.followAuthor() } }) {
        MIRAFollowAvatar(url: model.note.user?.profileImage, size: 52)
      }
      .buttonStyle(.plain)

      Text(model.note.user?.displayName ?? "mira")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)

      Text(noteAge(model.note.createdAt))
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)

      Spacer()
    }
  }

  private var noteBody: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(model.note.body ?? "")
        .font(.system(size: 23, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)

      if let media = model.note.mediaUrl, !media.isEmpty {
        MIRAAdaptiveMediaView(
          urls: [media],
          cornerRadius: 18,
          maxSingleImageHeight: mediaHeight,
          carouselHeight: mediaHeight,
          singleImageContentMode: .fill
        )
        .frame(maxWidth: .infinity, minHeight: mediaHeight, maxHeight: mediaHeight)
      }
    }
  }

  private var noteActions: some View {
    HStack(spacing: 30) {
      NoteDetailAction(systemImage: model.note.reacted == true ? "heart.fill" : "heart", value: model.note.reactionsCount ?? 0, tint: model.note.reacted == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary) {
        Task { await model.toggleReaction() }
      }
      NoteDetailAction(systemImage: "bubble.left", value: model.note.commentsCount ?? 0, tint: MIRATheme.Color.textSecondary) {}
      NoteDetailAction(systemImage: "paperplane", value: model.note.sharesCount ?? 0, tint: MIRATheme.Color.textSecondary) {
        Task { await model.recordShare() }
      }
      Spacer()
    }
  }

  private var commentsList: some View {
    LazyVStack(spacing: MIRATheme.Space.lg) {
      ForEach(model.comments) { comment in
        NoteReplyRowNative(comment: comment)
      }
    }
  }

  private var replyBar: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: model.note.user?.profileImage, size: 38)
      TextField("Add your reply...", text: $draft, axis: .vertical)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .focused($replyFocused)
      Button {} label: {
        Image(systemName: "photo")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 42, height: 42)
      }
      .buttonStyle(.plain)
      Button {} label: {
        Text("GIF")
          .font(.system(size: 18, weight: .heavy))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 54, height: 42)
          .overlay(Capsule().stroke(MIRATheme.Color.textPrimary, lineWidth: 3))
      }
      .buttonStyle(.plain)
      Button {
        let text = draft
        draft = ""
        Task { await model.sendReply(text) }
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 25, weight: .bold))
          .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MIRATheme.Color.textMuted.opacity(0.55) : MIRATheme.Color.forest)
          .frame(width: 38, height: 42)
      }
      .buttonStyle(.plain)
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .frame(height: 62)
    .background(MIRATheme.Color.surfaceSoft.opacity(0.82))
    .clipShape(Capsule())
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, 8)
    .padding(.bottom, MIRATheme.Space.sm)
    .background(MIRATheme.Color.surface.opacity(0.98))
  }
}

private func noteAge(_ value: String?) -> String {
  guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "" }
  let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  if hours < 24 { return "\(hours)h" }
  return "\(hours / 24)d"
}

private struct NoteDetailAction: View {
  let systemImage: String
  let value: Int
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 28, weight: .regular))
          .foregroundStyle(tint)
        Text("\(value)")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .frame(minHeight: 40)
    }
    .buttonStyle(.plain)
  }
}

private struct NoteReplyRowNative: View {
  let comment: MIRAComment

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      RemoteAvatar(url: comment.user?.profileImage, size: 46)
      VStack(alignment: .leading, spacing: 5) {
        Text(comment.user?.displayName ?? "user")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Text(comment.text)
          .font(.system(size: 19, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineSpacing(3)
        HStack(spacing: 26) {
          Text(noteAge(comment.createdAt))
          Text("Reply")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      }
      Spacer()
      HStack(spacing: 6) {
        Image(systemName: comment.likedByMe == true ? "heart.fill" : "heart")
          .font(.system(size: 27, weight: .regular))
          .foregroundStyle(comment.likedByMe == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary)
        Text("\(comment.likesCount ?? 0)")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .frame(minWidth: 58, minHeight: 46)
    }
  }
}
