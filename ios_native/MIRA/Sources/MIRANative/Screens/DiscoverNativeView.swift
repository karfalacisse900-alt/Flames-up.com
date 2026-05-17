import SwiftUI
import UIKit

@MainActor
final class DiscoverNativeModel: ObservableObject {
  @Published var notes: [MIRANote] = []
  @Published var stories: [MIRAStoryGroup] = []
  @Published var isLoading = false
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    isLoading = notes.isEmpty && stories.isEmpty
    defer { isLoading = false }
    notes = (try? await api.get("/notes?limit=14")) ?? []
    let loadedStories: [MIRAStoryGroup] = (try? await api.get("/statuses")) ?? []
    stories = loadedStories.filter { ($0.statuses?.isEmpty == false) }
  }
}

public struct DiscoverNativeView: View {
  @StateObject private var model: DiscoverNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: DiscoverNativeModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        discoverHeader

        ScrollView {
          VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
            storyRail

            notesSection
          }
          .padding(.top, MIRATheme.Space.xs)
          .padding(.bottom, MIRATheme.Space.xxl)
        }
      }
      .background(MIRATheme.Color.appBackground)
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: MIRANote.self) { note in
        NoteDetailNativeView(note: note, api: model.api)
      }
      .task { await model.load() }
    }
  }

  private var discoverHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Text("Discover")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
      NavigationLink(destination: SearchUsersNativeView(api: model.api)) {
        MIRAHeaderCircleButton(systemImage: "magnifyingglass")
      }
      NavigationLink(destination: CreateNoteNativeView(api: model.api)) {
        MIRAHeaderCircleButton(systemImage: "plus")
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, 6)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var notesSection: some View {
    let width = min(max(UIScreen.main.bounds.width * 0.68, 228), min(278, UIScreen.main.bounds.width - 78))
    let height = width * 1.18

    return VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      HStack {
        Text("Notes")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Spacer()
        NavigationLink(destination: CreateNoteNativeView(api: model.api)) {
          Image(systemName: "plus")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(MIRATheme.Color.forest)
            .clipShape(Circle())
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MIRATheme.Space.md) {
          if model.isLoading && model.notes.isEmpty {
            ForEach(0..<2, id: \.self) { _ in
              NoteCardSkeletonNative(width: width, height: height)
            }
          } else if model.notes.isEmpty {
            EmptyNoteCardNative(width: width, height: height)
          } else {
            ForEach(model.notes) { note in
              NavigationLink(value: note) {
                NoteCardNative(note: note, width: width, height: height)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, MIRATheme.Space.md)
      }
    }
  }

  private var storyRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MIRATheme.Space.md) {
        NavigationLink(destination: CreateStoryNativeView(api: model.api)) {
          StoryBubbleNative(name: "You", avatarURL: nil, hasUnviewed: false, isAdd: true)
        }
        .buttonStyle(.plain)

        if model.isLoading && model.stories.isEmpty {
          ForEach(0..<5, id: \.self) { index in
            StoryBubblePlaceholder(index: index)
          }
        } else {
          ForEach(model.stories) { group in
            StoryBubbleNative(name: group.displayName, avatarURL: group.userProfileImage, hasUnviewed: group.hasUnviewed == true, isAdd: false)
          }
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.sm)
    }
  }
}

private struct StoryBubbleNative: View {
  let name: String
  let avatarURL: String?
  let hasUnviewed: Bool
  let isAdd: Bool

  var body: some View {
    VStack(spacing: 5) {
      ZStack(alignment: .bottomTrailing) {
        RemoteAvatar(url: avatarURL, size: 58)
          .overlay(Circle().stroke(hasUnviewed ? MIRATheme.Color.forest : MIRATheme.Color.hairline, lineWidth: hasUnviewed ? 2 : 1))
        if isAdd {
          Circle()
            .fill(MIRATheme.Color.forest)
            .frame(width: 19, height: 19)
            .overlay(Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
            .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
        }
      }
      Text(name)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .lineLimit(1)
        .frame(width: 64)
    }
  }
}

private struct StoryBubblePlaceholder: View {
  let index: Int

  var body: some View {
    VStack(spacing: 5) {
      Circle()
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 58, height: 58)
      RoundedRectangle(cornerRadius: 4)
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 40, height: 8)
    }
    .redacted(reason: .placeholder)
  }
}

private struct NoteCardNative: View {
  let note: MIRANote
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        MIRAFollowAvatar(url: note.user?.profileImage, size: 36)
        HStack(spacing: 5) {
          Text(note.user?.displayName ?? "mira")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Text(noteAge(note.createdAt))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        Spacer(minLength: 4)
        Image(systemName: "ellipsis")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }

      Text(note.body ?? "New note")
        .font(.system(size: 15, weight: .semibold))
        .lineSpacing(2)
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(note.mediaUrl?.isEmpty == false ? 2 : 4)

      if let media = note.mediaUrl, !media.isEmpty {
        RemoteMediaView(url: media, isVideo: media.isVideoURL)
          .frame(maxWidth: .infinity)
          .frame(height: min(width * 0.70, height * 0.50))
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      } else {
        Spacer(minLength: 0)
      }

      HStack(spacing: MIRATheme.Space.sm) {
        NoteActionNative(systemImage: note.reacted == true ? "heart.fill" : "heart", value: note.reactionsCount ?? 0)
        NoteActionNative(systemImage: "bubble.left", value: note.commentsCount ?? 0)
        Spacer()
        NoteActionNative(systemImage: "paperplane", value: note.sharesCount ?? 0)
      }
      .padding(.top, 2)
    }
    .padding(12)
    .frame(width: width, height: height, alignment: .topLeading)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
  }
}

private struct CreateNoteCardNative: View {
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack(spacing: 9) {
        RemoteAvatar(url: nil, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text("Your note")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text("Photo or text")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      }

      Spacer()
      VStack(spacing: 8) {
        Image(systemName: "plus")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 46, height: 46)
          .background(MIRATheme.Color.forest)
          .clipShape(Circle())
        Text("Create a note")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text("Add a photo, GIF, or thought.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      Spacer()
    }
    .padding(MIRATheme.Space.md)
    .frame(width: width, height: height)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
  }
}

private struct NoteCardSkeletonNative: View {
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack {
        Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 40, height: 40)
        RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 120, height: 16)
      }
      RoundedRectangle(cornerRadius: 8).fill(MIRATheme.Color.surfaceSoft).frame(height: 18)
      RoundedRectangle(cornerRadius: 18).fill(MIRATheme.Color.surfaceSoft).frame(height: min(width * 0.62, height * 0.46))
      Spacer()
    }
    .padding(14)
    .frame(width: width, height: height)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .redacted(reason: .placeholder)
  }
}

private struct EmptyNoteCardNative: View {
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: "text.bubble")
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text("No notes yet")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text("Be the first to start one.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
    .frame(width: width, height: height)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
  }
}

private struct NoteActionNative: View {
  let systemImage: String
  let value: Int

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .regular))
      Text(compact(value))
        .font(.system(size: 13, weight: .semibold))
    }
    .foregroundStyle(MIRATheme.Color.textSecondary)
    .frame(minHeight: 32)
  }
}

private func noteAge(_ value: String?) -> String {
  guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "now" }
  let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
  if minutes < 1 { return "now" }
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  if hours < 24 { return "\(hours)h" }
  return "\(hours / 24)d"
}

private func compact(_ value: Int) -> String {
  if value >= 1_000_000 { return "\(value / 1_000_000)M" }
  if value >= 1_000 { return "\(value / 1_000)K" }
  return "\(value)"
}
