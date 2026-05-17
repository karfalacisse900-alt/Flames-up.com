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
}

public struct NoteDetailNativeView: View {
  @StateObject private var model: NoteDetailNativeModel
  @State private var draft = ""
  private var mediaHeight: CGFloat {
    if let media = model.note.mediaUrl, !media.isEmpty {
      return min(MIRAMediaSizing.feedHeight(for: [media]), 520)
    }
    return 0
  }

  public init(note: MIRANote, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: NoteDetailNativeModel(note: note, api: api))
  }

  public var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          HStack(spacing: MIRATheme.Space.sm) {
            Button(action: { Task { await model.followAuthor() } }) {
              MIRAFollowAvatar(url: model.note.user?.profileImage, size: 44)
            }
            .buttonStyle(.plain)

            Text(model.note.user?.displayName ?? "mira")
              .font(.system(size: 17, weight: .semibold))
            Spacer()
            MIRAIconButton(systemImage: "ellipsis") {}
          }

          Text(model.note.body ?? "")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineSpacing(3)

          if let media = model.note.mediaUrl, !media.isEmpty {
            MIRAAdaptiveMediaView(
              urls: [media],
              cornerRadius: MIRATheme.Radius.large,
              maxSingleImageHeight: mediaHeight,
              carouselHeight: mediaHeight
            )
          }

          HStack(spacing: MIRATheme.Space.lg) {
            MIRAStatButton(systemImage: "heart", value: model.note.reactionsCount ?? 0) {}
            MIRAStatButton(systemImage: "bubble.left", value: model.note.commentsCount ?? 0) {}
            Spacer()
            MIRAStatButton(systemImage: "paperplane", value: model.note.sharesCount ?? 0) {}
          }

          Divider()

          ForEach(model.comments) { comment in
            CommentRowNative(comment: comment)
          }
        }
        .padding(MIRATheme.Space.md)
      }

      replyBar
    }
    .background(MIRATheme.Color.appBackground)
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
  }

  private var replyBar: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      TextField("Add your reply...", text: $draft, axis: .vertical)
        .font(.system(size: 15, weight: .regular))
        .padding(.horizontal, MIRATheme.Space.md)
        .frame(minHeight: 46)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
      MIRAIconButton(systemImage: "photo") {}
      MIRAIconButton(systemImage: "arrow.up") {
        let text = draft
        draft = ""
        Task { await model.sendReply(text) }
      }
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .top) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }
}

private struct CommentRowNative: View {
  let comment: MIRAComment

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 34)
      VStack(alignment: .leading, spacing: MIRATheme.Space.xs) {
        Text(comment.user?.displayName ?? "user")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Text(comment.text)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        HStack(spacing: MIRATheme.Space.lg) {
          Text("Reply")
          Text("View replies")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      }
      Spacer()
      Image(systemName: "heart")
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .frame(width: 40, height: 40)
    }
  }
}
