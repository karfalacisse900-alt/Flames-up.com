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
  @StateObject private var model: NoteDetailNativeModel
  @State private var draft = ""
  @State private var showMenu = false
  private var mediaHeight: CGFloat {
    if let media = model.note.mediaUrl, !media.isEmpty {
      return min(MIRAMediaSizing.feedHeight(for: [media], width: UIScreen.main.bounds.width - 32), 430)
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
              .font(.system(size: 16, weight: .semibold))
            Text(noteAge(model.note.createdAt))
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted)
            Spacer()
            Button {
              showMenu = true
            } label: {
              Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textMuted)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
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
            MIRAStatButton(systemImage: model.note.reacted == true ? "heart.fill" : "heart", value: model.note.reactionsCount ?? 0) {
              Task { await model.toggleReaction() }
            }
            MIRAStatButton(systemImage: "bubble.left", value: model.note.commentsCount ?? 0) {}
            Spacer()
            MIRAStatButton(systemImage: "paperplane", value: model.note.sharesCount ?? 0) {
              Task { await model.recordShare() }
            }
          }

          Divider()

          ForEach(model.comments) { comment in
            CommentRowNative(comment: comment)
          }
        }
        .padding(MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.xs)
      }

      replyBar
    }
    .background(MIRATheme.Color.appBackground)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showMenu = true
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
      }
    }
    .confirmationDialog("Note options", isPresented: $showMenu) {
      Button("Not interested", role: .destructive) {}
      Button("Report", role: .destructive) {
        Task { await model.report(reason: "other") }
      }
      Button("Cancel", role: .cancel) {}
    }
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

private func noteAge(_ value: String?) -> String {
  guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "" }
  let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  if hours < 24 { return "\(hours)h" }
  return "\(hours / 24)d"
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
