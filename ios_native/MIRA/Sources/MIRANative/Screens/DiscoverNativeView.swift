import SwiftUI
import UIKit

@MainActor
final class DiscoverNativeModel: ObservableObject {
  @Published var stories: [MIRAStoryGroup] = []
  @Published var isLoading = true
  @Published var isLoadingStories = true
  let api: MIRAAPIClient
  private let storiesCacheKey = "native.discover.stories.v2"
  private var hasLoadedFreshStories = false

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    MIRAPerformanceTimeline.mark("discover_load_start")
    if stories.isEmpty, let cachedStories: [MIRAStoryGroup] = await MIRALocalJSONCache.load([MIRAStoryGroup].self, key: storiesCacheKey) {
      stories = cachedStories
      isLoadingStories = false
      MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "stories_cache")
    }

    if !hasLoadedFreshStories && stories.isEmpty { isLoadingStories = true }
    updateLoadingState()
    Task { await self.loadStories() }
  }

  private func loadStories() async {
    guard !hasLoadedFreshStories else { return }
    hasLoadedFreshStories = true
    if stories.isEmpty {
      isLoadingStories = true
      updateLoadingState()
    }
    defer {
      isLoadingStories = false
      updateLoadingState()
    }
    do {
      let loadedStories: [MIRAStoryGroup] = try await api.get("/statuses")
      let visibleStories = loadedStories.filter { ($0.statuses?.isEmpty == false) }
      stories = visibleStories
      await MIRALocalJSONCache.save(visibleStories, key: storiesCacheKey)
      if !visibleStories.isEmpty {
        MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "stories_network")
      }
    } catch {
      if stories.isEmpty { hasLoadedFreshStories = false }
    }
  }

  private func updateLoadingState() {
    isLoading = isLoadingStories
  }
}

private struct DiscoverChallenge: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let systemImage: String
  let colors: [Color]
  let filterIDs: Set<String>
}

private struct DiscoverChallengeFilter: Identifiable {
  let id: String
  let title: String
}

private let discoverChallenges: [DiscoverChallenge] = [
  .init(
    id: "night-out",
    title: "Night out",
    subtitle: "Best after-dark moment",
    systemImage: "moon.stars.fill",
    colors: [Color(red: 0.12, green: 0.12, blue: 0.20), Color(red: 0.48, green: 0.18, blue: 0.40)],
    filterIDs: ["night-out", "nightlife"]
  ),
  .init(
    id: "best-fit",
    title: "Best fit",
    subtitle: "Show the look",
    systemImage: "tshirt.fill",
    colors: [Color(red: 0.10, green: 0.24, blue: 0.22), Color(red: 0.18, green: 0.55, blue: 0.44)],
    filterIDs: ["best-fit", "style"]
  ),
  .init(
    id: "food-find",
    title: "Food find",
    subtitle: "What did you order?",
    systemImage: "fork.knife",
    colors: [Color(red: 0.58, green: 0.26, blue: 0.12), Color(red: 0.90, green: 0.58, blue: 0.24)],
    filterIDs: ["food", "cafe"]
  ),
  .init(
    id: "trip-dump",
    title: "Trip dump",
    subtitle: "Vacation or quick escape",
    systemImage: "airplane",
    colors: [Color(red: 0.10, green: 0.28, blue: 0.48), Color(red: 0.20, green: 0.58, blue: 0.82)],
    filterIDs: ["trip", "travel"]
  ),
  .init(
    id: "golden-hour",
    title: "Golden hour",
    subtitle: "Best light today",
    systemImage: "sun.max.fill",
    colors: [Color(red: 0.70, green: 0.38, blue: 0.10), Color(red: 0.98, green: 0.74, blue: 0.28)],
    filterIDs: ["golden-hour", "trip", "cafe"]
  ),
  .init(
    id: "friends-moment",
    title: "Friends moment",
    subtitle: "A candid with your circle",
    systemImage: "person.2.fill",
    colors: [Color(red: 0.20, green: 0.20, blue: 0.46), Color(red: 0.50, green: 0.42, blue: 0.82)],
    filterIDs: ["friends", "nightlife"]
  ),
]

private let discoverChallengeFilters: [DiscoverChallengeFilter] = [
  .init(id: "all", title: "All"),
  .init(id: "night-out", title: "Night out"),
  .init(id: "nightlife", title: "Nightlife"),
  .init(id: "best-fit", title: "Best fit"),
  .init(id: "food", title: "Food"),
  .init(id: "trip", title: "Trip"),
  .init(id: "cafe", title: "Cafe"),
  .init(id: "friends", title: "Friends"),
  .init(id: "golden-hour", title: "Golden hour"),
]

public struct DiscoverNativeView: View {
  @StateObject private var model: DiscoverNativeModel
  @State private var selectedStoryGroup: MIRAStoryGroup?
  @State private var isShowingCreatePost = false
  @State private var selectedChallengeFilter = "all"

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: DiscoverNativeModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        discoverHeader

        ScrollView {
          LazyVStack(alignment: .leading, spacing: MIRATheme.Space.xl) {
            storyRail

            challengesSection
          }
          .padding(.top, MIRATheme.Space.xs)
          .padding(.bottom, MIRATheme.Space.xxl + MIRATheme.Space.lg)
        }
      }
      .background(MIRATheme.Color.appBackground)
      .toolbar(.hidden, for: .navigationBar)
      .fullScreenCover(item: $selectedStoryGroup) { group in
        StoryViewerNativeView(group: group, api: model.api)
      }
      .fullScreenCover(isPresented: $isShowingCreatePost) {
        CreatePostNativeView(api: model.api)
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
      Button {
        isShowingCreatePost = true
      } label: {
        MIRAHeaderCircleButton(systemImage: "plus")
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, 6)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var challengesSection: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      sectionHeader(title: "Challenges", subtitle: "Pick a vibe and post into the moment.")

      challengeFilterRail

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 154), spacing: MIRATheme.Space.sm)], spacing: MIRATheme.Space.sm) {
        ForEach(filteredChallenges) { challenge in
          DiscoverChallengeCard(challenge: challenge) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isShowingCreatePost = true
          }
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
  }

  private var challengeFilterRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MIRATheme.Space.sm) {
        ForEach(discoverChallengeFilters) { filter in
          Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
              selectedChallengeFilter = filter.id
            }
          } label: {
            Text(filter.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(selectedChallengeFilter == filter.id ? .white : MIRATheme.Color.textPrimary)
              .padding(.horizontal, 15)
              .frame(height: 40)
              .background(selectedChallengeFilter == filter.id ? MIRATheme.Color.forest : MIRATheme.Color.surfaceRaised)
              .clipShape(Capsule())
              .overlay(
                Capsule()
                  .stroke(selectedChallengeFilter == filter.id ? Color.clear : MIRATheme.Color.hairline, lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
  }

  private var filteredChallenges: [DiscoverChallenge] {
    if selectedChallengeFilter == "all" { return discoverChallenges }
    return discoverChallenges.filter { $0.filterIDs.contains(selectedChallengeFilter) }
  }

  private func sectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text(subtitle)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private var storyRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MIRATheme.Space.md) {
        NavigationLink(destination: CreateStoryNativeView(api: model.api)) {
          StoryBubbleNative(name: "You", avatarURL: nil, hasUnviewed: false, isAdd: true)
        }
        .buttonStyle(.plain)

        if model.isLoadingStories && model.stories.isEmpty {
          ForEach(0..<5, id: \.self) { index in
            StoryBubblePlaceholder(index: index)
          }
        } else if model.stories.isEmpty {
          StoryEmptyBubble()
        } else {
          ForEach(model.stories) { group in
            Button {
              selectedStoryGroup = group
            } label: {
              StoryBubbleNative(name: group.displayName, avatarURL: group.userProfileImage, hasUnviewed: group.hasUnviewed == true, isAdd: false)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.sm)
    }
  }
}

private struct StoryViewerNativeView: View {
  let group: MIRAStoryGroup
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var selectedIndex = 0
  @State private var message = ""

  private var stories: [MIRAStatusPreview] {
    group.statuses?.isEmpty == false ? group.statuses! : []
  }

  private var currentStory: MIRAStatusPreview? {
    guard stories.indices.contains(selectedIndex) else { return nil }
    return stories[selectedIndex]
  }

  var body: some View {
    ZStack {
      Color(red: 0.04, green: 0.05, blue: 0.06).ignoresSafeArea()

      VStack(spacing: 0) {
        storyCanvas
          .padding(.horizontal, 0)

        bottomComposer
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.top, 12)
          .padding(.bottom, MIRATheme.Space.md)
      }
    }
    .statusBarHidden(false)
    .task(id: currentStory?.id) {
      guard let id = currentStory?.id else { return }
      let _: EmptyResponse? = try? await api.post("/statuses/\(id)/view", body: EmptyBody())
    }
  }

  private var storyCanvas: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        if let mediaURL = currentStory?.mediaURL {
          RemoteMediaView(url: mediaURL, isVideo: mediaURL.isVideoURL, shouldPlay: true)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(MIRATheme.Color.forest)
            .overlay {
              Text(currentStory?.content?.isEmpty == false ? currentStory!.content! : "Story")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(28)
            }
        }

        HStack(spacing: 0) {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { goToPreviousStory() }
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { goToNextStory() }
        }
        .padding(.top, 92)

        VStack(spacing: 13) {
          progressRail
            .padding(.top, 14)
          storyTopBar
        }
        .padding(.horizontal, MIRATheme.Space.md)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(maxHeight: .infinity)
  }

  private var progressRail: some View {
    HStack(spacing: 5) {
      ForEach(Array(stories.enumerated()), id: \.offset) { index, _ in
        Capsule()
          .fill(index <= selectedIndex ? Color.white.opacity(0.92) : Color.white.opacity(0.38))
          .frame(height: 3)
      }
    }
  }

  private var storyTopBar: some View {
    HStack(spacing: 10) {
      RemoteAvatar(url: group.userProfileImage, size: 44)
      Text(group.displayName)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
      Text(storyAge(currentStory?.createdAt))
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white.opacity(0.78))
      Spacer()
      Button {} label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
      }
      .buttonStyle(.plain)
      Button { dismiss() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 33, weight: .light))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
      }
      .buttonStyle(.plain)
    }
  }

  private func goToPreviousStory() {
    if selectedIndex > 0 {
      selectedIndex -= 1
    }
  }

  private func goToNextStory() {
    if selectedIndex < stories.count - 1 {
      selectedIndex += 1
    } else {
      dismiss()
    }
  }

  private var bottomComposer: some View {
    HStack(spacing: 14) {
      TextField("Send message...", text: $message)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(height: 56)
        .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1.4))

      Button {} label: {
        Image(systemName: "heart")
          .font(.system(size: 30, weight: .regular))
          .foregroundStyle(.white)
          .frame(width: 46, height: 46)
      }
      .buttonStyle(.plain)

      Button {} label: {
        Image(systemName: "paperplane")
          .font(.system(size: 30, weight: .regular))
          .foregroundStyle(.white)
          .frame(width: 46, height: 46)
      }
      .buttonStyle(.plain)
    }
  }
}

private struct StoryBubbleNative: View {
  let name: String
  let avatarURL: String?
  let hasUnviewed: Bool
  let isAdd: Bool

  var body: some View {
    VStack(spacing: 7) {
      ZStack(alignment: .bottomTrailing) {
        RemoteAvatar(url: avatarURL, size: 92)
          .overlay(Circle().stroke(hasUnviewed ? MIRATheme.Color.forest : MIRATheme.Color.hairline, lineWidth: hasUnviewed ? 3 : 1))
        if isAdd {
          Circle()
            .fill(MIRATheme.Color.forest)
            .frame(width: 28, height: 28)
            .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
            .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 3))
        }
      }
      Text(name)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
        .frame(width: 104)
    }
  }
}

private struct StoryBubblePlaceholder: View {
  let index: Int

  var body: some View {
    VStack(spacing: 7) {
      Circle()
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 92, height: 92)
      RoundedRectangle(cornerRadius: 4)
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 58, height: 10)
    }
    .redacted(reason: .placeholder)
  }
}

private struct StoryEmptyBubble: View {
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "sparkles")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 40, height: 40)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text("No stories yet")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text("Fresh stories will appear here.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 76)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
  }
}

private struct DiscoverChallengeCard: View {
  let challenge: DiscoverChallenge
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: challenge.systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.18))
            .clipShape(Circle())
          Spacer()
          Text("Challenge")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.82))
            .textCase(.uppercase)
        }

        Spacer(minLength: 6)

        Text(challenge.title)
          .font(.system(size: 23, weight: .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.82)

        Text(challenge.subtitle)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.82))
          .lineLimit(2)

        HStack(spacing: 6) {
          Text("Join")
            .font(.system(size: 13, weight: .bold))
          Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.white.opacity(0.18))
        .clipShape(Capsule())
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
      .background {
        LinearGradient(colors: challenge.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
      }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        Circle()
          .fill(.white.opacity(0.12))
          .frame(width: 86, height: 86)
          .offset(x: 22, y: 28)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Join \(challenge.title) challenge")
  }
}

private func storyAge(_ value: String?) -> String {
  guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "now" }
  let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
  if minutes < 1 { return "now" }
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  if hours < 24 { return "\(hours)h" }
  return "\(hours / 24)d"
}
