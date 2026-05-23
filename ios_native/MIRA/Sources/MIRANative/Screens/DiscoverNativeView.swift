import SwiftUI
import UIKit

@MainActor
final class DiscoverNativeModel: ObservableObject {
  @Published var stories: [MIRAStoryGroup] = []
  @Published var posts: [MIRAPost] = []
  @Published var isLoading = true
  @Published var isLoadingStories = true
  @Published var isLoadingPosts = true
  @Published var errorMessage: String?
  let api: MIRAAPIClient
  private let storiesCacheKey = "native.discover.stories.v3"
  private let postsCacheKey = "native.discover.posts.v1"
  private var hasLoadedFreshStories = false
  private var hasLoadedFreshPosts = false

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    MIRAPerformanceTimeline.mark("discover_load_start")
    if posts.isEmpty, let cachedPosts: [MIRAPost] = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey) {
      posts = cachedPosts
      isLoadingPosts = false
      MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_cache")
    }
    if stories.isEmpty, let cachedStories: [MIRAStoryGroup] = await MIRALocalJSONCache.load([MIRAStoryGroup].self, key: storiesCacheKey) {
      stories = cachedStories
      isLoadingStories = false
      MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "stories_cache")
    }

    if !hasLoadedFreshPosts && posts.isEmpty { isLoadingPosts = true }
    if !hasLoadedFreshStories && stories.isEmpty { isLoadingStories = true }
    updateLoadingState()
    Task { await self.loadPosts() }
    Task { await self.loadStories() }
  }

  private func loadPosts() async {
    guard !hasLoadedFreshPosts else { return }
    hasLoadedFreshPosts = true
    if posts.isEmpty {
      isLoadingPosts = true
      updateLoadingState()
    }
    defer {
      isLoadingPosts = false
      updateLoadingState()
    }
    do {
      var loaded: [MIRAPost] = try await api.get("/posts/feed?limit=60")
      if loaded.isEmpty {
        loaded = (try? await api.get("/posts/world-board?limit=60")) ?? []
      }
      posts = loaded
      await MIRALocalJSONCache.save(loaded, key: postsCacheKey)
      if !loaded.isEmpty {
        MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_network")
      }
    } catch {
      if let fallback: [MIRAPost] = try? await api.get("/posts/world-board?limit=60"), !fallback.isEmpty {
        posts = fallback
        await MIRALocalJSONCache.save(fallback, key: postsCacheKey)
        MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_fallback")
      } else if posts.isEmpty {
        hasLoadedFreshPosts = false
      }
    }
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
    isLoading = isLoadingStories || isLoadingPosts
  }

  func hidePost(_ post: MIRAPost) {
    posts.removeAll { $0.id == post.id }
    let snapshot = posts
    Task { await MIRALocalJSONCache.save(snapshot, key: postsCacheKey) }
  }

  func reportPost(_ post: MIRAPost) async {
    do {
      let _: EmptyResponse? = try await api.post(
        "/reports",
        body: PostReportBody(
          reportedType: "post",
          reportedId: post.id,
          reason: "other",
          details: "Reported from the Discover post menu."
        )
      )
      errorMessage = nil
    } catch {
      errorMessage = "Could not send report. Try again in a moment."
    }
  }
}

private struct DiscoverGalleryFilter: Identifiable {
  let id: String
  let title: String
  let keywords: [String]
}

private let discoverGalleryFilters: [DiscoverGalleryFilter] = [
  .init(id: "all", title: "All", keywords: []),
  .init(id: "travel", title: "Travel", keywords: ["trip", "travel", "vacation", "beach", "hotel"]),
  .init(id: "dining", title: "Dining", keywords: ["food", "restaurant", "dinner", "lunch", "brunch", "eat", "cafe", "coffee"]),
  .init(id: "outfits", title: "Outfits", keywords: ["fit", "outfit", "style", "fashion", "look"]),
  .init(id: "home", title: "Home", keywords: ["home", "room", "apartment", "house"]),
  .init(id: "relationship", title: "Relationship", keywords: ["relationship", "date", "couple", "friends", "love"])
]

public struct DiscoverNativeView: View {
  @StateObject private var model: DiscoverNativeModel
  @State private var selectedStoryGroup: MIRAStoryGroup?
  @State private var isStoryViewerVisible = false
  @State private var selectedGalleryFilter = "all"
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: DiscoverNativeModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      ZStack {
        VStack(spacing: 0) {
          discoverHeader

          ScrollView {
            LazyVStack(alignment: .leading, spacing: MIRATheme.Space.md) {
              storyRail

              gallerySection
            }
            .padding(.top, MIRATheme.Space.xs)
            .padding(.bottom, MIRATheme.Space.xxl + MIRATheme.Space.lg)
          }
        }
        .background(MIRATheme.Color.appBackground)

        storyViewerOverlay
      }
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.tab)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar(selectedStoryGroup == nil ? .visible : .hidden, for: .tabBar)
      .task { await model.load() }
    }
  }

  @ViewBuilder
  private var storyViewerOverlay: some View {
    if let group = selectedStoryGroup {
      ZStack {
        Color(red: 0.04, green: 0.05, blue: 0.06).ignoresSafeArea()
        StoryViewerNativeView(group: group, api: model.api, onClose: closeStoryViewer)
      }
      .opacity(isStoryViewerVisible ? 1 : 0)
      .scaleEffect(reduceMotion || isStoryViewerVisible ? 1 : 0.982)
      .offset(y: reduceMotion || isStoryViewerVisible ? 0 : 18)
      .ignoresSafeArea()
      .zIndex(50)
      .transition(.opacity)
      .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.28), value: isStoryViewerVisible)
    }
  }

  private func openStoryViewer(_ group: MIRAStoryGroup) {
    selectedStoryGroup = group
    isStoryViewerVisible = false
    DispatchQueue.main.async {
      withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.28)) {
        isStoryViewerVisible = true
      }
    }
  }

  private func closeStoryViewer() {
    withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.22)) {
      isStoryViewerVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.11 : 0.23)) {
      if !isStoryViewerVisible {
        selectedStoryGroup = nil
      }
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
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, 6)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var gallerySection: some View {
    VStack(alignment: .leading, spacing: 6) {
      galleryFilterRail

      if model.isLoadingPosts && model.posts.isEmpty {
        LazyVGrid(columns: galleryGridColumns, spacing: 1) {
          ForEach(0..<18, id: \.self) { index in
            DiscoverGallerySkeletonTile(index: index)
          }
        }
      } else if filteredGalleryPosts.isEmpty {
        DiscoverGalleryEmptyTile()
          .padding(.horizontal, MIRATheme.Space.md)
      } else {
        LazyVGrid(columns: galleryGridColumns, spacing: 1) {
          ForEach(filteredGalleryPosts) { post in
            NavigationLink(destination: PostDetailNativeView(post: post, api: model.api)) {
              DiscoverPostGalleryTile(post: post)
            }
            .buttonStyle(.plain)
            .contextMenu {
              Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await model.reportPost(post) }
              } label: {
                Label("Report", systemImage: "flag")
              }

              Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.hidePost(post)
              } label: {
                Label("Not interested", systemImage: "eye.slash")
              }
            }
          }
        }
      }
    }
  }

  private var galleryGridColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
  }

  private var galleryFilterRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 34) {
        ForEach(discoverGalleryFilters) { filter in
          Button {
            withAnimation(.easeInOut(duration: 0.18)) {
              selectedGalleryFilter = filter.id
            }
          } label: {
            Text(filter.title)
              .font(.system(size: 18, weight: selectedGalleryFilter == filter.id ? .semibold : .regular))
              .foregroundStyle(selectedGalleryFilter == filter.id ? MIRATheme.Color.textPrimary : MIRATheme.Color.textMuted)
              .frame(height: 36)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
    .frame(height: 40)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 0.5)
    }
  }

  private var galleryPosts: [MIRAPost] {
    let mediaPosts = model.posts.filter { !$0.mediaURLs.isEmpty }
    return mediaPosts.isEmpty ? model.posts : mediaPosts
  }

  private var filteredGalleryPosts: [MIRAPost] {
    guard
      selectedGalleryFilter != "all",
      let filter = discoverGalleryFilters.first(where: { $0.id == selectedGalleryFilter })
    else {
      return galleryPosts
    }
    let matches = galleryPosts.filter { post in
      let haystack = [
        post.title,
        post.caption,
        post.content,
        post.location,
        post.placeName,
        post.postType
      ]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")
      return filter.keywords.contains { haystack.contains($0) }
    }
    return matches.isEmpty ? galleryPosts : matches
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
      HStack(spacing: 10) {
        NavigationLink(destination: CreateStoryNativeView(api: model.api)) {
          StoryBubbleNative(name: "You", avatarURL: nil, hasUnviewed: false, isAdd: true)
        }
        .buttonStyle(.miraPress)

        if model.isLoadingStories && model.stories.isEmpty {
          ForEach(0..<5, id: \.self) { index in
            StoryBubblePlaceholder(index: index)
          }
        } else if model.stories.isEmpty {
          StoryEmptyBubble()
        } else {
          ForEach(model.stories) { group in
            Button {
              openStoryViewer(group)
            } label: {
              StoryBubbleNative(name: group.displayName, avatarURL: group.userProfileImage, hasUnviewed: group.hasUnviewed == true, isAdd: false)
            }
            .buttonStyle(.miraPress)
          }
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, 4)
      .padding(.bottom, 2)
    }
  }
}

private struct StoryViewerNativeView: View {
  let group: MIRAStoryGroup
  let api: MIRAAPIClient
  let onClose: () -> Void
  @State private var selectedIndex = 0
  @State private var localStories: [MIRAStatusPreview]?
  @State private var currentUserId: String?
  @State private var showStoryMenu = false
  @State private var isCanvasVisible = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var stories: [MIRAStatusPreview] {
    localStories ?? (group.statuses?.isEmpty == false ? group.statuses! : [])
  }

  private var currentStory: MIRAStatusPreview? {
    guard stories.indices.contains(selectedIndex) else { return nil }
    return stories[selectedIndex]
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Color(red: 0.04, green: 0.05, blue: 0.06).ignoresSafeArea()

      storyCanvas

      storyBottomActions
        .padding(.horizontal, MIRATheme.Space.lg)
        .padding(.bottom, 10)
    }
    .statusBarHidden(false)
    .opacity(isCanvasVisible ? 1 : 0.001)
    .scaleEffect(reduceMotion || isCanvasVisible ? 1 : 0.992)
    .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.24), value: isCanvasVisible)
    .onAppear {
      withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.24)) {
        isCanvasVisible = true
      }
    }
    .task(id: currentStory?.id) {
      guard let id = currentStory?.id else { return }
      let _: EmptyResponse? = try? await api.post("/statuses/\(id)/view", body: EmptyBody())
    }
    .task {
      if localStories == nil {
        localStories = group.statuses ?? []
      }
      if currentUserId == nil {
        let me: MIRAUser? = try? await api.get("/auth/me")
        currentUserId = me?.id
      }
    }
    .confirmationDialog("Story options", isPresented: $showStoryMenu, titleVisibility: .visible) {
      if currentUserId == group.userId {
        Button("Delete story", role: .destructive) {
          Task { await deleteCurrentStory() }
        }
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var storyCanvas: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        if let mediaURL = currentStory?.mediaURL {
          RemoteMediaView(url: mediaURL, isVideo: mediaURL.isVideoURL, shouldPlay: true)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        .padding(.top, 76)

        VStack(spacing: 9) {
          progressRail
            .padding(.top, 10)
          storyTopBar
        }
        .padding(.horizontal, 12)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(maxHeight: .infinity)
    .id(currentStory?.id ?? "empty-story")
    .transition(.opacity)
    .animation(.easeInOut(duration: reduceMotion ? 0.08 : 0.16), value: currentStory?.id)
  }

  private var progressRail: some View {
    HStack(spacing: 5) {
      ForEach(Array(stories.enumerated()), id: \.offset) { index, _ in
        Capsule()
          .fill(index <= selectedIndex ? Color.white.opacity(0.92) : Color.white.opacity(0.38))
          .frame(height: 2.5)
      }
    }
  }

  private var storyTopBar: some View {
    HStack(spacing: 8) {
      RemoteAvatar(url: group.userProfileImage, size: 34)
      Text(group.displayName)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
      Text(storyAge(currentStory?.createdAt))
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white.opacity(0.78))
      Spacer()
      Button { showStoryMenu = true } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 34, height: 34)
      }
      .buttonStyle(.miraPress)
      Button { closeStoryViewer() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 27, weight: .light))
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
      }
      .buttonStyle(.miraPress)
    }
  }

  private func goToPreviousStory() {
    if selectedIndex > 0 {
      withAnimation(.easeInOut(duration: 0.18)) {
        selectedIndex -= 1
      }
    }
  }

  private func goToNextStory() {
    if selectedIndex < stories.count - 1 {
      withAnimation(.easeInOut(duration: 0.18)) {
        selectedIndex += 1
      }
    } else {
      closeStoryViewer()
    }
  }

  private func deleteCurrentStory() async {
    guard let id = currentStory?.id else { return }
    do {
      let _: EmptyResponse = try await api.delete("/statuses/\(id)")
      var nextStories = stories
      nextStories.removeAll { $0.id == id }
      localStories = nextStories
      if nextStories.isEmpty {
        closeStoryViewer()
      } else {
        withAnimation(.easeInOut(duration: 0.18)) {
          selectedIndex = min(selectedIndex, max(0, nextStories.count - 1))
        }
      }
    } catch {
      // Keep the story visible if the backend rejects the delete.
    }
  }

  private func closeStoryViewer() {
    withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.18)) {
      isCanvasVisible = false
    }
    onClose()
  }

  private var storyBottomActions: some View {
    HStack(spacing: 14) {
      Spacer()
      Button {} label: {
        Image(systemName: "heart")
          .font(.system(size: 24, weight: .regular))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
      }
      .buttonStyle(.miraPress)

      Button {} label: {
        Image(systemName: "paperplane")
          .font(.system(size: 24, weight: .regular))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
      }
      .buttonStyle(.miraPress)
    }
  }
}

private struct StoryBubbleNative: View {
  let name: String
  let avatarURL: String?
  let hasUnviewed: Bool
  let isAdd: Bool

  var body: some View {
    VStack(spacing: 4) {
      ZStack(alignment: .bottomTrailing) {
        RemoteAvatar(url: avatarURL, size: 58)
          .overlay(Circle().stroke(hasUnviewed ? MIRATheme.Color.forest : MIRATheme.Color.hairline, lineWidth: hasUnviewed ? 2 : 1))
        if isAdd {
          Circle()
            .fill(MIRATheme.Color.forest)
            .frame(width: 20, height: 20)
            .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
        }
      }
      Text(name)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
        .frame(width: 66)
    }
    .frame(width: 68)
  }
}

private struct StoryBubblePlaceholder: View {
  let index: Int

  var body: some View {
    VStack(spacing: 4) {
      Circle()
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 58, height: 58)
      RoundedRectangle(cornerRadius: 4)
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 42, height: 8)
    }
    .frame(width: 68)
    .redacted(reason: .placeholder)
  }
}

private struct StoryEmptyBubble: View {
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "sparkles")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 32, height: 32)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text("No stories yet")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text("Fresh stories will appear here.")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 54)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
  }
}

private struct DiscoverPostGalleryTile: View {
  let post: MIRAPost

  var body: some View {
    GeometryReader { proxy in
      let tileHeight = proxy.size.width * MIRAMediaSizing.profileGridRatio
      ZStack(alignment: .topTrailing) {
        if let media = post.mediaURLs.first {
          RemoteMediaView(url: media, isVideo: media.isVideoURL, shouldPlay: false)
            .frame(width: proxy.size.width, height: tileHeight)
        } else {
          ZStack {
            MIRATheme.Color.surfaceSoft
            Text(post.titleText)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .multilineTextAlignment(.center)
              .lineLimit(4)
              .padding(8)
          }
          .frame(width: proxy.size.width, height: tileHeight)
        }

        if post.mediaURLs.first?.isVideoURL == true {
          Image(systemName: "play.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(7)
            .background(.black.opacity(0.36))
            .clipShape(Circle())
            .padding(6)
        } else if post.mediaURLs.count > 1 {
          Image(systemName: "square.on.square")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(7)
            .background(.black.opacity(0.36))
            .clipShape(Circle())
            .padding(6)
        }
      }
      .frame(width: proxy.size.width, height: tileHeight)
      .clipped()
    }
    .aspectRatio(1.0 / MIRAMediaSizing.profileGridRatio, contentMode: .fit)
    .clipped()
    .contentShape(Rectangle())
    .accessibilityLabel(post.titleText)
  }
}

private struct DiscoverGallerySkeletonTile: View {
  let index: Int

  var body: some View {
    RoundedRectangle(cornerRadius: 0)
      .fill(index.isMultiple(of: 2) ? MIRATheme.Color.surfaceSoft : MIRATheme.Color.surfaceRaised)
      .aspectRatio(1.0 / MIRAMediaSizing.profileGridRatio, contentMode: .fit)
      .redacted(reason: .placeholder)
  }
}

private struct DiscoverGalleryEmptyTile: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text("Posts will appear here.")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 150)
    .background(MIRATheme.Color.surfaceRaised)
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
