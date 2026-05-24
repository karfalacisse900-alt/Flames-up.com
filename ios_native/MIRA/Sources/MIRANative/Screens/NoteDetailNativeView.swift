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
          noteHeader
            .padding(.top, 18)
          noteBody(contentWidth: contentWidth)
            .padding(.top, 14)
          noteActions
            .padding(.top, 15)
          Rectangle()
            .fill(MIRATheme.Color.hairline.opacity(0.52))
            .frame(height: 0.7)
            .padding(.top, 18)
          commentsList
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .safeAreaInset(edge: .bottom) {
        replyBar(horizontalInset: horizontalInset)
      }
    }
    .background(Color.white.ignoresSafeArea())
    .miraScreenEnter(.push)
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
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 48, height: 48, alignment: .leading)
      }
      .buttonStyle(.plain)

      Spacer()

      Button {
        showMenu = true
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 48, height: 48, alignment: .trailing)
      }
      .buttonStyle(.plain)
    }
  }

  private var noteHeader: some View {
    HStack(spacing: 10) {
      Button(action: { Task { await model.followAuthor() } }) {
        MIRAFollowAvatar(url: model.note.user?.profileImage, size: 48)
      }
      .buttonStyle(.plain)

      if let userId = model.note.user?.id, !userId.isEmpty {
        NavigationLink(destination: UserProfileNativeView(userId: userId, api: model.api)) {
          Text(model.note.user?.displayName ?? "mira")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
        .buttonStyle(.plain)
      } else {
        Text(model.note.user?.displayName ?? "mira")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
      }

      Text(noteAge(model.note.createdAt))
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)

      Spacer()
    }
  }

  private func noteBody(contentWidth: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(model.note.body ?? "")
        .font(.system(size: 21, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineSpacing(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)

      if let media = model.note.mediaUrl, !media.isEmpty {
        let mediaHeight = noteMediaHeight(for: media, width: contentWidth)
        MIRAAdaptiveMediaView(
          urls: [media],
          cornerRadius: 18,
          maxSingleImageHeight: mediaHeight,
          carouselHeight: mediaHeight,
          singleImageContentMode: .fill
        )
        .frame(width: contentWidth, height: mediaHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
    }
  }

  private func noteMediaHeight(for media: String, width: CGFloat) -> CGFloat {
    guard width > 0 else { return 0 }
    let ideal = MIRAMediaSizing.feedHeight(for: [media], width: width)
    let lower = width * 0.58
    let upper = min(width * 0.78, UIScreen.main.bounds.height * 0.38)
    return min(max(ideal, lower), upper)
  }

  private var noteActions: some View {
    HStack(spacing: 31) {
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

  private func replyBar(horizontalInset: CGFloat) -> some View {
    HStack(spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: model.note.user?.profileImage, size: 34)
      TextField("Add your reply...", text: $draft, axis: .vertical)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .focused($replyFocused)
        .lineLimit(1...3)
        .layoutPriority(1)
      Button {} label: {
        Image(systemName: "photo")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 36, height: 38)
      }
      .buttonStyle(.plain)
      Button {} label: {
        Text("GIF")
          .font(.system(size: 16, weight: .heavy))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 46, height: 38)
          .overlay(Capsule().stroke(MIRATheme.Color.textPrimary, lineWidth: 2.5))
      }
      .buttonStyle(.plain)
      Button {
        let text = draft
        draft = ""
        Task { await model.sendReply(text) }
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 23, weight: .bold))
          .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MIRATheme.Color.textMuted.opacity(0.55) : MIRATheme.Color.forest)
          .frame(width: 34, height: 38)
      }
      .buttonStyle(.plain)
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 12)
    .frame(height: 58)
    .frame(maxWidth: .infinity)
    .background(Color(red: 0.985, green: 0.985, blue: 0.975))
    .clipShape(Capsule())
    .padding(.horizontal, horizontalInset)
    .padding(.top, 8)
    .padding(.bottom, MIRATheme.Space.sm)
    .background(Color.white.opacity(0.98))
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
      HStack(spacing: 7) {
        Image(systemName: systemImage)
          .font(.system(size: 25, weight: .regular))
          .foregroundStyle(tint)
        Text("\(value)")
          .font(.system(size: 17, weight: .medium))
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
    HStack(alignment: .top, spacing: 12) {
      RemoteAvatar(url: comment.user?.profileImage, size: 46)
      VStack(alignment: .leading, spacing: 5) {
        Text(comment.user?.displayName ?? "user")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
        Text(comment.text)
          .font(.system(size: 18, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineSpacing(3.5)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 26) {
          Text(noteAge(comment.createdAt))
          Text("Reply")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer()
      HStack(spacing: 6) {
        Image(systemName: comment.likedByMe == true ? "heart.fill" : "heart")
          .font(.system(size: 24, weight: .regular))
          .foregroundStyle(comment.likedByMe == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary)
        Text("\(comment.likesCount ?? 0)")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .frame(width: 52)
      .frame(minHeight: 42)
    }
  }
}
