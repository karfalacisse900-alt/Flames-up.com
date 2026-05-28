import AVFoundation
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
  private let postsCacheKeyPrefix = "native.discover.posts.v3"
  private var activePostsCategory = "all"
  private var hasLoadedFreshStories = false
  private var hasLoadedFreshPosts = false
  private var hasScheduledPostsLoad = false
  private var hasScheduledStoriesLoad = false

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func prepareForStartup() async {
    MIRAPerformanceTimeline.mark("discover_startup_prepare")
    await hydrateCachedContentIfNeeded()
    if posts.isEmpty { isLoadingPosts = true }
    if stories.isEmpty { isLoadingStories = true }
    updateLoadingState()
    await load()
  }

  func load() async {
    MIRAPerformanceTimeline.mark("discover_load_start")
    await hydrateCachedContentIfNeeded()

    if !hasLoadedFreshPosts && posts.isEmpty { isLoadingPosts = true }
    if !hasLoadedFreshStories && stories.isEmpty { isLoadingStories = true }
    updateLoadingState()
    if !hasScheduledPostsLoad {
      hasScheduledPostsLoad = true
      Task { await self.loadPosts(category: self.activePostsCategory) }
    }
    if !hasScheduledStoriesLoad {
      hasScheduledStoriesLoad = true
      Task { await self.loadStories() }
    }
  }

  private func hydrateCachedContentIfNeeded() async {
    if posts.isEmpty, let cachedPosts: [MIRAPost] = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey(for: activePostsCategory)) {
      posts = cachedPosts
      isLoadingPosts = false
      MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_cache")
    }
    if stories.isEmpty, let cachedStories: [MIRAStoryGroup] = await MIRALocalJSONCache.load([MIRAStoryGroup].self, key: storiesCacheKey) {
      stories = cachedStories
      isLoadingStories = false
      MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "stories_cache")
    }
  }

  func selectCategory(_ category: String) async {
    let normalized = normalizedDiscoverCategory(category)
    guard normalized != activePostsCategory || posts.isEmpty else { return }
    activePostsCategory = normalized
    hasLoadedFreshPosts = false
    hasScheduledPostsLoad = false
    if let cachedPosts: [MIRAPost] = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey(for: normalized)) {
      posts = cachedPosts
      isLoadingPosts = false
    } else {
      posts = []
      isLoadingPosts = true
    }
    updateLoadingState()
    await loadPosts(category: normalized, force: true)
  }

  private func loadPosts(category requestedCategory: String = "all", force: Bool = false) async {
    let category = normalizedDiscoverCategory(requestedCategory)
    guard force || !hasLoadedFreshPosts else { return }
    activePostsCategory = category
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
      let encodedCategory = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "all"
      var loaded: [MIRAPost] = try await api.get("/discover?category=\(encodedCategory)&limit=36")
      if loaded.isEmpty && category == "all" {
        loaded = (try? await api.get("/posts/feed?limit=24")) ?? []
      }
      if loaded.isEmpty && category == "all" {
        loaded = (try? await api.get("/posts/world-board?limit=24")) ?? []
      }
      if posts != loaded {
        posts = loaded
      }
      await MIRALocalJSONCache.save(loaded, key: postsCacheKey(for: category))
      if !loaded.isEmpty {
        MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_network")
      }
    } catch {
      if category == "all", let fallback: [MIRAPost] = try? await api.get("/posts/world-board?limit=24"), !fallback.isEmpty {
        if posts != fallback {
          posts = fallback
        }
        await MIRALocalJSONCache.save(fallback, key: postsCacheKey(for: category))
        MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_fallback")
      } else if posts.isEmpty {
        hasLoadedFreshPosts = false
        hasScheduledPostsLoad = false
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
      if stories != visibleStories {
        stories = visibleStories
      }
      await MIRALocalJSONCache.save(visibleStories, key: storiesCacheKey)
      if !visibleStories.isEmpty {
        MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "stories_network")
      }
    } catch {
      if stories.isEmpty {
        hasLoadedFreshStories = false
        hasScheduledStoriesLoad = false
      }
    }
  }

  private func updateLoadingState() {
    isLoading = isLoadingStories || isLoadingPosts
  }

  func hidePost(_ post: MIRAPost) {
    posts.removeAll { $0.id == post.id }
    let snapshot = posts
    Task { await MIRALocalJSONCache.save(snapshot, key: postsCacheKey(for: activePostsCategory)) }
  }

  func hidePosts(byUserId userId: String) {
    posts.removeAll { $0.userId == userId }
    let snapshot = posts
    Task { await MIRALocalJSONCache.save(snapshot, key: postsCacheKey(for: activePostsCategory)) }
  }

  func blockAuthor(_ post: MIRAPost) async {
    guard let userId = post.userId, !userId.isEmpty else { return }
    let previous = posts
    posts.removeAll { $0.userId == userId }
    do {
      let _: EmptyResponse? = try await api.post("/users/\(userId)/block", body: EmptyBody())
      let snapshot = posts
      Task { await MIRALocalJSONCache.save(snapshot, key: postsCacheKey(for: activePostsCategory)) }
      errorMessage = nil
    } catch {
      posts = previous
      errorMessage = "Could not block this user. Try again in a moment."
    }
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

  private func postsCacheKey(for category: String) -> String {
    "\(postsCacheKeyPrefix).\(normalizedDiscoverCategory(category))"
  }

  private func normalizedDiscoverCategory(_ value: String) -> String {
    let allowed = Set(discoverGalleryFilters.map(\.id))
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allowed.contains(clean) ? clean : "all"
  }
}

private let discoverGalleryFilters: [DiscoverGalleryFilter] = [
  .init(id: "all"),
  .init(id: "photography"),
  .init(id: "outdoors"),
  .init(id: "outfits"),
  .init(id: "food"),
  .init(id: "travel"),
  .init(id: "events"),
  .init(id: "nightlife"),
  .init(id: "art"),
  .init(id: "lifestyle"),
  .init(id: "fitness"),
  .init(id: "pets"),
  .init(id: "cars"),
  .init(id: "beauty")
]

private struct DiscoverGalleryFilter: Identifiable {
  let id: String
}

public struct DiscoverNativeView: View {
  @StateObject private var model: DiscoverNativeModel
  @State private var selectedStoryGroup: MIRAStoryGroup?
  @State private var selectedGalleryFilter = "all"
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportSourcePost: MIRAPost?
  @State private var isReportSheetPresented = false
  @EnvironmentObject private var localization: MIRALocalization

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: DiscoverNativeModel(api: api))
  }

  init(api: MIRAAPIClient, model: DiscoverNativeModel) {
    _model = StateObject(wrappedValue: model)
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
      }
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.tab)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar((selectedStoryGroup == nil && !isReportSheetPresented) ? .visible : .hidden, for: .tabBar)
      .task { await model.load() }
      .miraFullScreenOverlay(item: $selectedStoryGroup, background: .black) { group, dismissStory in
        StoryViewerNativeView(
          group: group,
          api: model.api,
          onClose: dismissStory,
          onReportStory: { target in
            dismissStory()
            DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.fullScreenClose) {
              reportSourcePost = nil
              reportTarget = target
              DispatchQueue.main.async {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
                  isReportSheetPresented = true
                }
              }
            }
          }
        )
      }
      .miraBottomSheet(
        isPresented: $isReportSheetPresented,
        preferredHeightFraction: 0.78,
        maxHeight: 700,
        onDismissed: {
          reportTarget = nil
          reportSourcePost = nil
        }
      ) { dismissReport in
        if let reportTarget {
          MIRAReportSheet(
            target: reportTarget,
            api: model.api,
            onSubmitted: { result in handleReportResult(result) },
            onClose: dismissReport
          )
        } else {
          Color.clear
        }
      }
    }
  }

  private func openStoryViewer(_ group: MIRAStoryGroup) {
    selectedStoryGroup = group
  }

  private func presentReport(for post: MIRAPost) {
    reportSourcePost = post
    reportTarget = MIRAReportTarget(
      targetType: "post",
      targetId: post.id,
      ownerUserId: post.userId,
      title: "Report post",
      subtitle: post.titleText
    )
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
        isReportSheetPresented = true
      }
    }
  }

  private func handleReportResult(_ result: MIRAReportResult) {
    guard let post = reportSourcePost else { return }
    if result.blocked, let userId = post.userId {
      model.hidePosts(byUserId: userId)
    } else if result.hidden {
      model.hidePost(post)
    }
  }

  private var discoverHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Text(localization.string("discover.title"))
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
            NavigationLink(destination: DiscoverPostDetailNativeView(post: post, api: model.api)) {
              DiscoverPostGalleryTile(post: post)
            }
            .buttonStyle(.plain)
            .contextMenu {
              discoverPostActions(post)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func discoverPostActions(_ post: MIRAPost) -> some View {
    Button(role: .destructive) {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      presentReport(for: post)
    } label: {
      Label(localization.string("common.report"), systemImage: "flag")
    }

    Button(role: .destructive) {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      Task { await model.blockAuthor(post) }
    } label: {
      Label(localization.string("common.block_user"), systemImage: "hand.raised")
    }

    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      model.hidePost(post)
    } label: {
      Label(localization.string("report.hide_content"), systemImage: "eye.slash")
    }

    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      model.hidePost(post)
    } label: {
      Label(localization.string("common.not_interested"), systemImage: "hand.thumbsdown")
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
            Task { await model.selectCategory(filter.id) }
          } label: {
            Text(localization.discoverCategoryLabel(filter.id))
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
    galleryPosts
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
  let onReportStory: (MIRAReportTarget) -> Void
  @State private var selectedIndex = 0
  @State private var localStories: [MIRAStatusPreview]?
  @State private var currentUserId: String?
  @State private var showStoryMenu = false
  @State private var isCanvasVisible = false
  @State private var isClosing = false
  @State private var replyText = ""
  @State private var storyAudioPlayer: AVPlayer?
  @State private var isStoryAudioPlaying = false
  @State private var isStoryAudioLoading = false
  @State private var resumeStoryAudioAfterInterruption = false
  @FocusState private var isReplyFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private var stories: [MIRAStatusPreview] {
    localStories ?? (group.statuses?.isEmpty == false ? group.statuses! : [])
  }

  private var currentStory: MIRAStatusPreview? {
    guard stories.indices.contains(selectedIndex) else { return nil }
    return stories[selectedIndex]
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      GeometryReader { proxy in
        let safeTop = proxy.safeAreaInsets.top
        let safeBottom = proxy.safeAreaInsets.bottom
        let bottomChromeHeight = max(74, safeBottom + 62)
        let topChromeHeight = max(2, safeTop + 2)
        let mediaHeight = max(360, proxy.size.height - bottomChromeHeight - topChromeHeight)

        VStack(spacing: 0) {
          storyCanvas
            .frame(width: proxy.size.width, height: mediaHeight)
            .padding(.top, topChromeHeight)

          Spacer(minLength: 0)

          storyBottomActions
            .padding(.horizontal, 13)
            .padding(.bottom, max(7, safeBottom + 1))
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }
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
    .task(id: currentStory?.id) {
      await prepareStoryAudioIfNeeded()
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
      } else {
        Button("Report story", role: .destructive) {
          reportCurrentStory()
        }
        Button("Block user", role: .destructive) {
          Task { await blockStoryOwner() }
        }
      }
      Button("Cancel", role: .cancel) {}
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        MIRAPlaybackCoordinator.resumeVisible(reason: "story_active")
        resumeStoryAudioIfNeeded()
      } else {
        pauseStoryAudioForInterruption()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { _ in
      pauseStoryAudioForInterruption()
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackMayResume)) { _ in
      resumeStoryAudioIfNeeded()
    }
    .onDisappear { stopStoryAudio() }
  }

  private var storyCanvas: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        if let mediaURL = currentStory?.mediaURL {
          RemoteMediaView(
            url: mediaURL,
            isVideo: mediaURL.isVideoURL,
            contentMode: .fill,
            shouldPlay: true,
            placeholderColor: storyFallbackColor,
            placeholderTint: MIRATheme.Color.textSecondary.opacity(0.68)
          )
            .frame(width: proxy.size.width, height: proxy.size.height)
        } else {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(storyFallbackColor)
            .overlay {
              Text(currentStory?.content?.isEmpty == false ? currentStory!.content! : "Story")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(storyTextColor)
                .multilineTextAlignment(.center)
                .padding(28)
            }
        }

        LinearGradient(
          colors: [.black.opacity(0.34), .black.opacity(0.08), .clear],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: min(170, proxy.size.height * 0.26))

        LinearGradient(
          colors: [.clear, .black.opacity(0.22)],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: min(190, proxy.size.height * 0.30))
        .frame(maxHeight: .infinity, alignment: .bottom)

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
            .padding(.top, 13)
          storyTopBar
        }
        .padding(.horizontal, 13)
      }
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .frame(maxWidth: .infinity)
    .transition(.opacity)
    .animation(.easeInOut(duration: reduceMotion ? 0.08 : 0.16), value: currentStory?.id)
  }

  private var progressRail: some View {
    HStack(spacing: 6) {
      ForEach(0..<max(stories.count, 1), id: \.self) { index in
        Capsule()
          .fill(index <= selectedIndex ? Color.white.opacity(0.96) : Color.white.opacity(0.36))
          .frame(height: 3.2)
      }
    }
  }

  private var storyTopBar: some View {
    HStack(spacing: 9) {
      RemoteAvatar(url: group.userProfileImage, size: 36)

      HStack(spacing: 7) {
        Text(group.displayName)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text("\u{00B7} \(storyAge(currentStory?.createdAt))")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.white.opacity(0.66))
          .lineLimit(1)
      }
      .layoutPriority(1)

      Spacer()

      if currentStory?.hasAudio == true {
        Button {
          toggleStoryAudio()
        } label: {
          ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(.black.opacity(0.34))
              .frame(width: 32, height: 32)
            if isStoryAudioLoading {
              ProgressView()
                .tint(.white)
                .scaleEffect(0.58)
            } else {
              Image(systemName: isStoryAudioPlaying ? "pause.fill" : "music.note")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: isStoryAudioPlaying ? 0 : 3, y: isStoryAudioPlaying ? 0 : 3)
            }
          }
          .frame(width: 36, height: 36)
        }
        .buttonStyle(.miraPress)
      }

      Button { closeStoryViewer() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 25, weight: .regular))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
      }
      .buttonStyle(.miraPress)
    }
  }

  private var storyBottomActions: some View {
    HStack(spacing: 12) {
      HStack(spacing: 10) {
        TextField("Message...", text: $replyText)
          .font(.system(size: 16, weight: .regular))
          .foregroundStyle(.white)
          .tint(.white)
          .focused($isReplyFocused)
          .submitLabel(.send)
          .onSubmit(sendStoryReplyDraft)

        Spacer(minLength: 4)

        if replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          HStack(spacing: 14) {
            Text("😍")
            Text("😂")
            Text("😳")
          }
          .font(.system(size: 25))
          .lineLimit(1)
        } else {
          Button(action: sendStoryReplyDraft) {
            Image(systemName: "paperplane.fill")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 30, height: 30)
          }
          .buttonStyle(.miraPress)
        }
      }
      .padding(.leading, 18)
      .padding(.trailing, 13)
      .frame(height: 48)
      .background(Color.white.opacity(0.18))
      .clipShape(Capsule())

      Button {} label: {
        Image(systemName: "heart")
          .font(.system(size: 29, weight: .regular))
          .foregroundStyle(.white)
          .frame(width: 38, height: 48)
      }
      .buttonStyle(.miraPress)

      Button { showStoryMenu = true } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 26, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 36, height: 48)
      }
      .buttonStyle(.miraPress)
    }
  }

  private var storyFallbackColor: Color {
    guard let value = currentStory?.backgroundColor, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return MIRATheme.Color.mediaPlaceholder
    }
    return Color(uiColor: UIColor(hex: value))
  }

  private var storyTextColor: Color {
    guard let value = currentStory?.textColor, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .white
    }
    return Color(uiColor: UIColor(hex: value))
  }

  @MainActor
  private func prepareStoryAudioIfNeeded() async {
    stopStoryAudio()
    guard let story = currentStory, story.hasAudio else { return }
    isStoryAudioLoading = true
    defer { isStoryAudioLoading = false }
    guard let stream = await storyAudioStreamURL(for: story), let url = URL(string: stream) else { return }
    let player = AVPlayer(url: url)
    storyAudioPlayer = player
    player.play()
    isStoryAudioPlaying = true
  }

  private func storyAudioStreamURL(for story: MIRAStatusPreview) async -> String? {
    let stream = story.audioStreamUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !stream.isEmpty { return stream }
    guard
      let encoded = story.audioTrackId?.trimmingCharacters(in: .whitespacesAndNewlines)
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
      !encoded.isEmpty
    else {
      return nil
    }
    do {
      let track: MIRAAudiusTrack = try await api.get("/music/audius/stream/\(encoded)")
      return track.streamUrl
    } catch {
      return nil
    }
  }

  private func toggleStoryAudio() {
    if isStoryAudioPlaying {
      resumeStoryAudioAfterInterruption = false
      storyAudioPlayer?.pause()
      isStoryAudioPlaying = false
    } else if let storyAudioPlayer {
      storyAudioPlayer.play()
      isStoryAudioPlaying = true
    } else {
      Task { await prepareStoryAudioIfNeeded() }
    }
  }

  private func stopStoryAudio() {
    storyAudioPlayer?.pause()
    storyAudioPlayer = nil
    isStoryAudioPlaying = false
    isStoryAudioLoading = false
    resumeStoryAudioAfterInterruption = false
  }

  private func pauseStoryAudioForInterruption() {
    resumeStoryAudioAfterInterruption = isStoryAudioPlaying
    storyAudioPlayer?.pause()
    isStoryAudioPlaying = false
  }

  private func resumeStoryAudioIfNeeded() {
    guard resumeStoryAudioAfterInterruption, let storyAudioPlayer else { return }
    storyAudioPlayer.play()
    isStoryAudioPlaying = true
    resumeStoryAudioAfterInterruption = false
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

  private func reportCurrentStory() {
    guard let story = currentStory else { return }
    onReportStory(
      MIRAReportTarget(
        targetType: "story",
        targetId: story.id,
        ownerUserId: story.userId ?? group.userId,
        title: "Report story",
        subtitle: story.content?.isEmpty == false ? story.content : group.displayName
      )
    )
  }

  private func blockStoryOwner() async {
    let ownerId = currentStory?.userId ?? group.userId
    guard !ownerId.isEmpty, ownerId != currentUserId else { return }
    let _: EmptyResponse? = try? await api.post("/users/\(ownerId)/block", body: EmptyBody())
    closeStoryViewer()
  }

  private func closeStoryViewer() {
    guard !isClosing else { return }
    isClosing = true
    let duration = reduceMotion ? 0.08 : 0.22
    withAnimation(.easeInOut(duration: duration)) {
      isCanvasVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
      onClose()
    }
  }

  private func sendStoryReplyDraft() {
    guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    replyText = ""
    isReplyFocused = false
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
        if let media = post.thumbnailMediaURLs.first {
          RemoteMediaView(
            url: media,
            isVideo: media.isVideoURL,
            shouldPlay: false,
            maxPixelSize: 560,
            showsVideoPlaceholderIcon: false
          )
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

        if post.thumbnailMediaURLs.count > 1 {
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
