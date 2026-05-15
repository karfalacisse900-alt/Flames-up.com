import SwiftUI

@MainActor
final class DiscoverNativeModel: ObservableObject {
  @Published var notes: [MIRANote] = []
  @Published var isLoading = false
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    isLoading = notes.isEmpty
    defer { isLoading = false }
    do {
      notes = try await api.get("/notes?limit=12")
    } catch {
      notes = []
    }
  }
}

public struct DiscoverNativeView: View {
  @StateObject private var model: DiscoverNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: DiscoverNativeModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.xl) {
          storyRail

          Text("Notes")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .padding(.horizontal, MIRATheme.Space.md)

          if model.notes.isEmpty && !model.isLoading {
            MIRAEmptyState(title: "No notes yet", message: "Short visual notes will show here.", systemImage: "text.bubble")
          } else {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: MIRATheme.Space.md) {
                ForEach(model.notes) { note in
                  NavigationLink(value: note) {
                    NoteCardNative(note: note)
                  }
                  .buttonStyle(.plain)
                }
              }
              .padding(.horizontal, MIRATheme.Space.md)
              .padding(.bottom, MIRATheme.Space.md)
            }
          }
        }
      }
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("Discover")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink(destination: SearchUsersNativeView(api: model.api)) {
            Image(systemName: "magnifyingglass")
          }
          NavigationLink(destination: CreateNoteNativeView(api: model.api)) {
            Image(systemName: "plus")
          }
        }
      }
      .navigationDestination(for: MIRANote.self) { note in
        NoteDetailNativeView(note: note, api: model.api)
      }
      .task { await model.load() }
      .refreshable { await model.load() }
    }
  }

  private var storyRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MIRATheme.Space.md) {
        ForEach(0..<8, id: \.self) { index in
          VStack(spacing: 8) {
            Circle()
              .stroke(MIRATheme.Color.forest.opacity(0.18), lineWidth: 2)
              .frame(width: 66, height: 66)
              .overlay(Circle().fill(MIRATheme.Color.surfaceSoft).padding(4))
            Text(index == 0 ? "You" : "Story")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.md)
    }
  }
}

private struct NoteCardNative: View {
  let note: MIRANote

  var body: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack(spacing: MIRATheme.Space.sm) {
        RemoteAvatar(url: note.user?.profileImage, size: 44)
        Text(note.user?.displayName ?? "mira")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        Spacer()
        Image(systemName: "ellipsis")
          .foregroundStyle(MIRATheme.Color.textMuted)
      }

      Text(note.body ?? "")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(3)

      if let media = note.mediaUrl, !media.isEmpty {
        RemoteMediaView(url: media, isVideo: media.isVideoURL)
          .frame(height: 250)
          .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
      }

      HStack(spacing: MIRATheme.Space.lg) {
        MIRAStatButton(systemImage: "heart", value: note.reactionsCount ?? 0) {}
        MIRAStatButton(systemImage: "bubble.left", value: note.commentsCount ?? 0) {}
        Spacer()
        MIRAStatButton(systemImage: "paperplane", value: note.sharesCount ?? 0) {}
      }
    }
    .padding(MIRATheme.Space.md)
    .frame(width: 330)
    .miraCardSurface()
  }
}
