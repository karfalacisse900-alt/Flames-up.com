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
    if posts.isEmpty, let cachedPosts = await cachedDiscoverPosts(for: activePostsCategory) {
      posts = scopedDiscoverPosts(cachedPosts, category: activePostsCategory)
      isLoadingPosts = false
      prefetchVisibleMedia(posts)
      MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_cache")
    }
    if stories.isEmpty, let cachedStories = await cachedDiscoverStories() {
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
    if let cachedPosts = await cachedDiscoverPosts(for: normalized) {
      posts = scopedDiscoverPosts(cachedPosts, category: normalized)
      isLoadingPosts = false
    } else if normalized != "all", let cachedAllPosts = await cachedDiscoverPosts(for: "all") {
      posts = scopedDiscoverPosts(cachedAllPosts, category: normalized)
      isLoadingPosts = posts.isEmpty
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
      var loaded: [MIRAPost] = scopedDiscoverPosts(try await api.get("/discover?category=\(encodedCategory)&limit=36"), category: category)
      if loaded.isEmpty && category != "all" {
        loaded = scopedDiscoverPosts((try? await api.get("/discover?category=all&limit=60")) ?? [], category: category)
      }
      if loaded.isEmpty && category == "all" {
        loaded = photoDiscoverPosts((try? await api.get("/posts/feed?limit=24")) ?? [])
      }
      if loaded.isEmpty && category != "all" {
        loaded = scopedDiscoverPosts((try? await api.get("/posts/feed?limit=60")) ?? [], category: category)
      }
      if loaded.isEmpty && category == "all" {
        loaded = photoDiscoverPosts((try? await api.get("/posts/world-board?limit=24")) ?? [])
      }
      if posts != loaded {
        posts = loaded
      }
      prefetchVisibleMedia(loaded)
      await MIRAAppCacheStore.shared.saveDiscoverPosts(loaded, category: category)
      if !loaded.isEmpty {
        MIRAPerformanceTimeline.markOnce("discover_first_content", detail: "posts_network")
      }
    } catch {
      if category == "all", let fallback: [MIRAPost] = try? await api.get("/posts/world-board?limit=24"), !fallback.isEmpty {
        let photoFallback = photoDiscoverPosts(fallback)
        guard !photoFallback.isEmpty else { return }
        if posts != photoFallback {
          posts = photoFallback
        }
        prefetchVisibleMedia(photoFallback)
        await MIRAAppCacheStore.shared.saveDiscoverPosts(photoFallback, category: category)
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
      await MIRAAppCacheStore.shared.saveDiscoverStories(visibleStories)
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

  private func prefetchVisibleMedia(_ posts: [MIRAPost]) {
    let previewURLs = posts
      .prefix(30)
      .flatMap { post in
        post.posterMediaURLs
          + post.thumbnailMediaURLs
          + post.feedMediaURLs.filter { !$0.isVideoURL }
      }
    let feedURLs = posts
      .prefix(12)
      .flatMap(\.feedMediaURLs)
      .filter { !$0.isVideoURL }
    guard !previewURLs.isEmpty || !feedURLs.isEmpty else { return }
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: previewURLs, maxPixelSize: 520, limit: 30)
      await MIRAImagePrefetcher.prefetch(urls: feedURLs, maxPixelSize: MIRAMediaSizing.feedTargetHeight, limit: 12)
    }
  }

  private func photoDiscoverPosts(_ values: [MIRAPost]) -> [MIRAPost] {
    values.filter { !$0.containsVideoMedia }
  }

  private func stableEngagementCount(current: Int?, incoming: Int?, toggledOn: Bool? = nil) -> Int? {
    guard let incoming else { return nil }
    if incoming == 0 {
      let currentValue = current ?? 0
      if toggledOn == true, currentValue > 0 { return currentValue }
      if toggledOn == false, currentValue > 1 { return currentValue - 1 }
    }
    return incoming
  }

  func hidePost(_ post: MIRAPost) {
    posts.removeAll { $0.id == post.id }
    let snapshot = posts
    Task { await MIRAAppCacheStore.shared.saveDiscoverPosts(snapshot, category: activePostsCategory) }
  }

  func hidePosts(byUserId userId: String) {
    posts.removeAll { $0.userId == userId }
    let snapshot = posts
    Task { await MIRAAppCacheStore.shared.saveDiscoverPosts(snapshot, category: activePostsCategory) }
  }

  func applyEngagementUpdate(_ update: MIRAPostEngagementUpdate) {
    guard let index = posts.firstIndex(where: { $0.id == update.postId }) else { return }
    posts[index] = posts[index].updating(
      liked: update.liked,
      likesCount: stableEngagementCount(current: posts[index].likesCount, incoming: update.likesCount, toggledOn: update.liked),
      commentsCount: update.commentsCount,
      saved: update.saved,
      savesCount: update.savesCount
    )
    let snapshot = posts
    Task { await MIRAAppCacheStore.shared.saveDiscoverPosts(snapshot, category: activePostsCategory) }
  }

  func blockAuthor(_ post: MIRAPost) async {
    guard let userId = post.userId, !userId.isEmpty else { return }
    let previous = posts
    posts.removeAll { $0.userId == userId }
    do {
      let _: EmptyResponse? = try await api.post("/users/\(userId)/block", body: EmptyBody())
      let snapshot = posts
      Task { await MIRAAppCacheStore.shared.saveDiscoverPosts(snapshot, category: activePostsCategory) }
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

  private func cachedDiscoverPosts(for category: String) async -> [MIRAPost]? {
    if let cached = await MIRAAppCacheStore.shared.loadDiscoverPosts(category: category) {
      return cached
    }
    return await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey(for: category), maxAge: 60 * 60 * 24 * 30)
  }

  private func cachedDiscoverStories() async -> [MIRAStoryGroup]? {
    if let cached = await MIRAAppCacheStore.shared.loadDiscoverStories() {
      return cached
    }
    return await MIRALocalJSONCache.load([MIRAStoryGroup].self, key: storiesCacheKey, maxAge: 60 * 60 * 24 * 30)
  }

  private func normalizedDiscoverCategory(_ value: String) -> String {
    let allowed = Set(discoverGalleryFilters.map(\.id))
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allowed.contains(clean) ? clean : "all"
  }

  private func normalizedSavedDiscoverCategory(_ value: String?) -> String? {
    guard let value else { return nil }
    let allowed = Set(discoverGalleryFilters.map(\.id).filter { $0 != "all" })
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "-", with: "_")
    return allowed.contains(clean) ? clean : nil
  }

  private func scopedDiscoverPosts(_ posts: [MIRAPost], category: String) -> [MIRAPost] {
    let photoPosts = photoDiscoverPosts(posts)
    let normalized = normalizedDiscoverCategory(category)
    guard normalized != "all" else { return photoPosts }
    return photoPosts.filter { postMatchesDiscoverCategory($0, category: normalized) }
  }

  private func postMatchesDiscoverCategory(_ post: MIRAPost, category: String) -> Bool {
    let normalized = normalizedDiscoverCategory(category)
    let savedCategories = [
      post.primaryCategory,
      post.category,
      post.userSelectedCategory,
      post.postType
    ].compactMap(normalizedSavedDiscoverCategory)
    if savedCategories.contains(normalized) { return true }

    let secondaryCategories = post.secondaryCategories?.values.compactMap(normalizedSavedDiscoverCategory) ?? []
    if secondaryCategories.contains(normalized) { return true }

    if let score = post.categoryScores?[normalized], score >= 30 { return true }

    let arraySignals = [
      post.tags?.values,
      post.detectedObjects?.values,
      post.captionKeywords?.values
    ].compactMap { $0 }.flatMap { $0 }
    let textSignals = [
      post.title,
      post.caption,
      post.content,
      post.location,
      post.displayLocationLabel,
      post.placeName,
      post.placeCategory,
      post.placeCity,
      post.placeCountry,
      post.detectedScene,
      post.placeType
    ].compactMap { $0 }
    let searchable = (arraySignals + textSignals).joined(separator: " ").lowercased()

    return discoverCategoryKeywords[normalized]?.contains { keyword in
      searchable.contains(keyword)
    } == true
  }
}

private let discoverGalleryFilters: [DiscoverGalleryFilter] = [
  .init(id: "all"),
  .init(id: "outfits"),
  .init(id: "outdoors"),
  .init(id: "photography"),
  .init(id: "food"),
  .init(id: "cafe"),
  .init(id: "travel"),
  .init(id: "events"),
  .init(id: "fitness"),
  .init(id: "beauty"),
  .init(id: "art"),
  .init(id: "nightlife"),
  .init(id: "places"),
  .init(id: "lifestyle")
]

private let discoverCategoryKeywords: [String: [String]] = [
  "outfits": ["outfit", "fit check", "clothes", "clothing", "style", "fashion", "streetwear", "shoes", "jacket", "dress"],
  "outdoors": ["outdoor", "outside", "park", "beach", "trail", "hiking", "nature", "mountain", "lake", "sunset", "trees", "forest", "sky"],
  "photography": ["photography", "camera", "portrait", "photo shoot", "street photo", "landscape", "lens", "film", "monochrome", "composition"],
  "food": ["food", "meal", "restaurant", "plate", "drink", "dessert", "pizza", "burger", "breakfast", "dinner"],
  "cafe": ["cafe", "coffee", "latte", "espresso", "bakery", "pastry", "brunch", "tea"],
  "travel": ["travel", "trip", "vacation", "hotel", "airport", "landmark", "tourist", "city", "bridge", "street", "architecture"],
  "events": ["event", "events", "concert", "festival", "meetup", "show", "game", "crowd", "stadium", "venue", "performance", "birthday", "wedding", "stage", "celebration"],
  "fitness": ["gym", "workout", "running", "fitness", "sport", "training", "yoga", "bike", "cycling"],
  "beauty": ["beauty", "makeup", "hair", "skincare", "nails", "salon", "cosmetic"],
  "art": ["art", "drawing", "painting", "design", "sketch", "mural", "gallery", "museum"],
  "nightlife": ["nightlife", "night", "club", "bar", "lounge", "party", "rooftop", "drinks", "neon"],
  "places": ["place", "venue", "store", "shop", "museum", "school", "market", "downtown", "location"],
  "lifestyle": ["lifestyle", "daily life", "friends", "home", "routine", "selfie", "people", "family"]
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
  @State private var singlePhotoPreviewPost: MIRAPost?
  @State private var isSinglePhotoPreviewPresented = false
  @EnvironmentObject private var localization: MIRALocalization
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
          .miraScrollFeel(.feed)
        }
        .background(MIRATheme.Color.appBackground)
      }
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.tab)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar((selectedStoryGroup == nil && !isReportSheetPresented && !isSinglePhotoPreviewPresented) ? .visible : .hidden, for: .tabBar)
      .miraStatusBarHidden(selectedStoryGroup != nil)
      .task { await model.load() }
      .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
        guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
        model.applyEngagementUpdate(update)
      }
      .miraFullScreenOverlay(item: $selectedStoryGroup, background: .black) { group, dismissStory in
        StoryViewerNativeView(
          group: group,
          allGroups: model.stories,
          api: model.api,
          onClose: dismissStory,
          onReportStory: { target in
            dismissStory()
            DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.fullScreenClose) {
              reportSourcePost = nil
              reportTarget = target
              DispatchQueue.main.async {
                withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
                  isReportSheetPresented = true
                }
              }
            }
          }
        )
      }
      .miraBottomSheet(
        isPresented: $isSinglePhotoPreviewPresented,
        preferredHeightFraction: 0.78,
        maxHeight: 720,
        onDismissed: { singlePhotoPreviewPost = nil }
      ) { dismissPreview in
        if let post = singlePhotoPreviewPost {
          DiscoverSinglePhotoPreviewSheet(
            post: post,
            api: model.api,
            onClose: dismissPreview,
            onReportComment: { comment in
              dismissPreview()
              DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
                presentReport(for: comment)
              }
            }
          )
        } else {
          Color.clear
        }
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
    prewarmStoryGroup(group)
    selectedStoryGroup = group
  }

  private func prewarmStoryGroup(_ group: MIRAStoryGroup) {
    let urls = orderedUniqueStoryMediaURLs((group.statuses ?? []).prefix(5).compactMap(\.mediaURL))
    guard !urls.isEmpty else { return }
    MIRAVideoPrewarmManager.shared.prewarm(urls: urls, keepOnly: Set(urls.prefix(2)))
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 1920, limit: 5)
    }
  }

  private func orderedUniqueStoryMediaURLs(_ urls: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for url in urls {
      let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      result.append(trimmed)
    }
    return result
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
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
        isReportSheetPresented = true
      }
    }
  }

  private func presentReport(for comment: MIRAComment) {
    reportSourcePost = nil
    reportTarget = MIRAReportTarget(
      targetType: "comment",
      targetId: comment.id,
      ownerUserId: comment.userId,
      title: "Report comment",
      subtitle: comment.text
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
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
            if shouldOpenSinglePhotoPreview(post) {
              Button {
                CaptroHaptics.light()
                singlePhotoPreviewPost = post
                withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
                  isSinglePhotoPreviewPresented = true
                }
              } label: {
                DiscoverPostGalleryTile(post: post)
              }
              .buttonStyle(.plain)
              .contextMenu {
                discoverPostActions(post)
              }
            } else {
              NavigationLink(destination: DiscoverPostDetailNativeView(post: post, api: model.api).miraHideTabBarOnAppear()) {
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
  }

  private func shouldOpenSinglePhotoPreview(_ post: MIRAPost) -> Bool {
    guard !post.containsVideoMedia else { return false }
    let mediaCount = max(post.feedMediaURLs.count, post.mediaURLs.count)
    return mediaCount <= 1
  }

  @ViewBuilder
  private func discoverPostActions(_ post: MIRAPost) -> some View {
    Button(role: .destructive) {
      CaptroHaptics.medium()
      presentReport(for: post)
    } label: {
      Label(localization.string("common.report"), systemImage: "flag")
    }

    Button(role: .destructive) {
      CaptroHaptics.medium()
      Task { await model.blockAuthor(post) }
    } label: {
      Label(localization.string("common.block_user"), systemImage: "hand.raised")
    }

    Button {
      CaptroHaptics.light()
      model.hidePost(post)
    } label: {
      Label(localization.string("report.hide_content"), systemImage: "eye.slash")
    }

    Button {
      CaptroHaptics.light()
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
            withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
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
    model.posts.filter(hasVisualPreview)
  }

  private var filteredGalleryPosts: [MIRAPost] {
    galleryPosts
  }

  private func hasVisualPreview(_ post: MIRAPost) -> Bool {
    guard !post.containsVideoMedia else { return false }
    return !(post.posterMediaURLs + post.thumbnailMediaURLs + post.feedMediaURLs + post.mediaURLs)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .isEmpty
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
        NavigationLink(destination: CreateStoryNativeView(api: model.api).miraHideTabBarOnAppear()) {
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

private struct DiscoverSinglePhotoPreviewSheet: View {
  @StateObject private var model: PostDetailModel
  @State private var isCommentsPresented = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let onClose: () -> Void
  let onReportComment: (MIRAComment) -> Void

  init(post: MIRAPost, api: MIRAAPIClient, onClose: @escaping () -> Void, onReportComment: @escaping (MIRAComment) -> Void) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
    self.onClose = onClose
    self.onReportComment = onReportComment
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          sheetChrome

          if let mediaURL {
            GeometryReader { proxy in
              let width = proxy.size.width
              RemoteMediaView(
                url: mediaURL,
                isVideo: false,
                placeholderURL: placeholderURL,
                fallbackURL: fallbackURL(for: mediaURL),
                contentMode: .fill,
                shouldPlay: false,
                maxPixelSize: MIRAMediaSizing.feedTargetHeight,
                showsVideoPlaceholderIcon: false
              )
              .frame(width: width, height: previewHeight(for: width))
              .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
              .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(height: previewHeight(for: UIScreen.main.bounds.width - (MIRATheme.Space.md * 2)))
          }

          previewActions

          if !headlineText.isEmpty {
            Text(headlineText)
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .fixedSize(horizontal: false, vertical: true)
          }

          if !captionText.isEmpty {
            Text(captionText)
              .font(.system(size: 15, weight: .regular))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(MIRATheme.Space.md)
      }
      .scrollIndicators(.hidden)
      .background(MIRATheme.Color.appBackground)
      .toolbar(.hidden, for: .navigationBar)
      .miraBottomSheet(
        isPresented: $isCommentsPresented,
        preferredHeightFraction: 0.72,
        maxHeight: 640
      ) { dismissComments in
        DiscoverDetailCommentsSheet(
          model: model,
          onClose: dismissComments,
          onReportComment: { comment in
            dismissComments()
            DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
              onReportComment(comment)
            }
          },
          onBlockCommentUser: { comment in
            dismissComments()
            Task { await model.blockCommentAuthor(comment) }
          }
        )
      }
      .task {
        await model.hydrateFromLocalCache()
        await model.refreshPost()
      }
      .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
        guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
        model.applyEngagementUpdate(update)
      }
    }
  }

  private var sheetChrome: some View {
    HStack {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.24))
        .frame(width: 42, height: 5)
      Spacer()
      Button {
        CaptroHaptics.light()
        onClose()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(width: 34, height: 34)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)
    }
  }

  private var previewActions: some View {
    HStack(spacing: 12) {
      if let userId = model.post.userId, !userId.isEmpty {
        NavigationLink(destination: UserProfileNativeView(userId: userId, api: model.api).miraHideTabBarOnAppear()) {
          authorSummary
        }
        .buttonStyle(.plain)
      } else {
        authorSummary
      }

      Spacer(minLength: 8)

      Button {
        CaptroHaptics.light()
        Task { await model.toggleLike() }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: model.post.isLiked == true ? "hand.thumbsup.fill" : "hand.thumbsup")
            .font(.system(size: 20, weight: .regular))
          Text(compactCount(model.post.likesCount ?? 0))
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(model.post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textPrimary)
        .frame(minWidth: 58, minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)

      Button {
        CaptroHaptics.light()
        isCommentsPresented = true
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "bubble.right")
            .font(.system(size: 20, weight: .regular))
          Text(compactCount(model.post.commentsCount ?? model.comments.count))
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minWidth: 58, minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)
    }
  }

  private var authorSummary: some View {
    HStack(spacing: 9) {
      RemoteAvatar(url: model.post.userProfileImage, size: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text(model.post.authorDisplayName)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        Text(relativeAge(model.post.createdAt))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
      }
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }

  private var mediaURL: String? {
    uniqueURLs(model.post.feedMediaURLs + model.post.mediaURLs).first { !$0.isVideoURL }
  }

  private var placeholderURL: String? {
    let current = mediaURL
    return uniqueURLs(model.post.thumbnailMediaURLs + model.post.posterMediaURLs)
      .first { !$0.isVideoURL && $0 != current }
  }

  private var headlineText: String {
    (model.post.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var captionText: String {
    let caption = (model.post.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let content = (model.post.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return caption.isEmpty ? content : caption
  }

  private func previewHeight(for width: CGFloat) -> CGFloat {
    let height = MIRAMediaSizing.feedHeight(for: [mediaURL ?? ""], aspectRatios: model.post.mediaHeightToWidthRatios, width: width)
    return min(height, UIScreen.main.bounds.height * 0.66)
  }

  private func fallbackURL(for media: String) -> String? {
    uniqueURLs(model.post.mediaURLs + model.post.feedMediaURLs)
      .first { !$0.isVideoURL && $0 != media && $0 != placeholderURL }
  }

  private func uniqueURLs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  private func compactCount(_ value: Int) -> String {
    if value >= 1_000_000 {
      return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
      return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
  }
}

private struct StoryThought: Codable, Identifiable, Hashable {
  let id: String
  let statusId: String?
  let userId: String?
  let body: String
  let createdAt: String?
  let userUsername: String?
  let userFullName: String?
  let userProfileImage: String?

  var displayName: String {
    if let userFullName, !userFullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return userFullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if MIRAUsernameRules.isValidPublicUsername(userUsername) {
      return MIRAUsernameRules.normalized(userUsername)
    }
    return "Someone"
  }
}

private struct StoryThoughtSubmitBody: Encodable {
  let body: String
}

private struct StoryThoughtBubbleState: Identifiable, Hashable {
  let id = UUID()
  let thought: StoryThought
}

private struct StoryViewerNativeView: View {
  let group: MIRAStoryGroup
  let allGroups: [MIRAStoryGroup]
  let api: MIRAAPIClient
  let onClose: () -> Void
  let onReportStory: (MIRAReportTarget) -> Void
  @State private var selectedIndex = 0
  @State private var localStories: [MIRAStatusPreview]?
  @State private var activeGroupOverride: MIRAStoryGroup?
  @State private var currentUserId: String?
  @State private var showStoryMenu = false
  @State private var isCanvasVisible = false
  @State private var isClosing = false
  @State private var replyText = ""
  @State private var storyThoughts: [StoryThought] = []
  @State private var visibleThoughts: [StoryThoughtBubbleState] = []
  @State private var thoughtPlaybackTask: Task<Void, Never>?
  @State private var isSendingThought = false
  @State private var thoughtErrorText: String?
  @State private var storyAudioPlayer: AVPlayer?
  @State private var isStoryAudioPlaying = false
  @State private var isStoryAudioLoading = false
  @State private var resumeStoryAudioAfterInterruption = false
  @State private var isSubmittingStoryLike = false
  @GestureState private var storyRailDragTranslation: CGFloat = 0
  @FocusState private var isReplyFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private var stories: [MIRAStatusPreview] {
    localStories ?? (activeGroup.statuses?.isEmpty == false ? activeGroup.statuses! : [])
  }

  private var activeGroup: MIRAStoryGroup {
    activeGroupOverride ?? group
  }

  private var storyRailGroups: [MIRAStoryGroup] {
    let available = allGroups.filter { $0.statuses?.isEmpty == false }
    return available.isEmpty ? [activeGroup] : available
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
        let mediaTopInset = storyMediaTopInset(safeTop: safeTop)

        ZStack {
          storyMediaLayer
            .frame(width: proxy.size.width, height: max(1, proxy.size.height - mediaTopInset))
            .clipShape(StoryTopRoundedRectangle(radius: 24))
            .padding(.top, mediaTopInset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .ignoresSafeArea(edges: [.horizontal, .bottom])

          LinearGradient(
            colors: [.black.opacity(0.28), .black.opacity(0.08), .clear],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: min(190, proxy.size.height * 0.26))
          .frame(maxHeight: .infinity, alignment: .top)
          .allowsHitTesting(false)

          LinearGradient(
            colors: [.clear, .black.opacity(0.24), .black.opacity(0.58)],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: min(330, proxy.size.height * 0.42))
          .frame(maxHeight: .infinity, alignment: .bottom)
          .allowsHitTesting(false)

          HStack(spacing: 0) {
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture { goToPreviousStory() }
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture { goToNextStory() }
          }
          .padding(.top, safeTop + 86)
          .padding(.bottom, safeBottom + 164)
          .simultaneousGesture(
            DragGesture(minimumDistance: 32, coordinateSpace: .local)
              .onEnded(handleStoryGroupSwipe)
          )

          storyTopBar
            .padding(.horizontal, 13)
            .padding(.top, safeTop + 42)
            .frame(maxHeight: .infinity, alignment: .top)

          storyThoughtOverlay
            .padding(.horizontal, 14)
            .padding(.bottom, safeBottom + 154)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)

          VStack(spacing: 12) {
            storyProfileCarousel
            storyBottomActions
              .padding(.horizontal, 13)
          }
          .padding(.bottom, max(8, safeBottom + 8))
          .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }
    .opacity(isCanvasVisible ? 1 : 0.001)
    .scaleEffect(reduceMotion || isCanvasVisible ? 1 : 0.992)
    .animation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion), value: isCanvasVisible)
    .miraStatusBarHidden(true)
    .onAppear {
      MIRAPlaybackCoordinator.resumeVisible(reason: "story_view_open")
      Task { await prewarmStoryMediaWindow() }
      withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
        isCanvasVisible = true
      }
    }
    .task(id: currentStory?.id) {
      guard let id = currentStory?.id else { return }
      let _: EmptyResponse? = try? await api.post("/statuses/\(id)/view", body: EmptyBody())
    }
    .task(id: storyPrewarmTaskID) {
      await prewarmStoryMediaWindow()
    }
    .task(id: currentStory?.id) {
      await prepareStoryAudioIfNeeded()
    }
    .task(id: currentStory?.id) {
      try? await Task.sleep(nanoseconds: 300_000_000)
      guard !Task.isCancelled else { return }
      await loadStoryThoughtsForCurrentStory()
    }
    .task {
      if localStories == nil {
        localStories = activeGroup.statuses ?? []
      }
      if currentUserId == nil {
        let me: MIRAUser? = try? await api.get("/auth/me")
        currentUserId = me?.id
      }
    }
    .confirmationDialog("Story options", isPresented: $showStoryMenu, titleVisibility: .visible) {
      if currentUserId == activeGroup.userId {
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
    .onDisappear {
      stopStoryAudio()
      thoughtPlaybackTask?.cancel()
      visibleThoughts.removeAll()
    }
  }

  private var storyMediaLayer: some View {
    ZStack {
      if let mediaURL = currentStory?.mediaURL {
        RemoteMediaView(
          url: mediaURL,
          isVideo: mediaURL.isVideoURL,
          contentMode: .fill,
          shouldPlay: !isClosing && scenePhase == .active,
          maxPixelSize: 1920,
          placeholderColor: storyFallbackColor,
          placeholderTint: MIRATheme.Color.textSecondary.opacity(0.68)
        )
      } else {
        Rectangle()
          .fill(storyFallbackColor)
          .overlay {
            Text(currentStory?.content?.isEmpty == false ? currentStory!.content! : "Story")
              .font(.system(size: 26, weight: .semibold))
              .foregroundStyle(storyTextColor)
              .multilineTextAlignment(.center)
              .padding(28)
          }
      }
    }
    .transition(.opacity)
    .animation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion), value: currentStory?.id)
  }

  private var storyThoughtOverlay: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(visibleThoughts.suffix(3)) { item in
        StoryThoughtBubbleView(thought: item.thought)
          .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .move(edge: .top))
          ))
      }
    }
  }

  private var storyProfileCarousel: some View {
    HStack(alignment: .bottom, spacing: 18) {
      storyRailBubble(storyRailNeighbor(offset: -1), isSelected: false)
        .frame(width: 76, height: 112)
        .opacity(storyRailNeighbor(offset: -1) == nil ? 0 : 1)

      storyRailBubble(activeGroup, isSelected: true)
        .frame(width: 116, height: 116)
        .zIndex(1)

      storyRailBubble(storyRailNeighbor(offset: 1), isSelected: false)
        .frame(width: 76, height: 112)
        .opacity(storyRailNeighbor(offset: 1) == nil ? 0 : 1)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 128)
    .padding(.top, 6)
    .offset(x: clampedStoryRailDrag)
    .animation(storyRailAnimation, value: activeGroup.userId)
    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.92, blendDuration: 0.02), value: storyRailDragTranslation)
    .highPriorityGesture(
      DragGesture(minimumDistance: 28, coordinateSpace: .local)
        .updating($storyRailDragTranslation) { value, state, _ in
          let horizontal = value.translation.width
          let vertical = value.translation.height
          guard abs(horizontal) > abs(vertical) * 1.15 else { return }
          state = horizontal
        }
        .onEnded(handleStoryGroupSwipe)
    )
  }

  private var storyPrewarmTaskID: String {
    "\(activeGroup.userId)|\(selectedIndex)|\(currentStory?.id ?? "none")"
  }

  private func storyMediaTopInset(safeTop: CGFloat) -> CGFloat {
    safeTop > 0 ? 18 : 14
  }

  private var clampedStoryRailDrag: CGFloat {
    let limit: CGFloat = 104
    return min(max(storyRailDragTranslation, -limit), limit)
  }

  private var storyRailAnimation: Animation {
    reduceMotion
      ? .easeOut(duration: CaptroMotion.Duration.reduced)
      : .interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.04)
  }

  @ViewBuilder
  private func storyRailBubble(_ railGroup: MIRAStoryGroup?, isSelected: Bool) -> some View {
    if let railGroup {
      Button {
        selectStoryGroup(railGroup)
      } label: {
        StoryViewerCarouselBubble(
          group: railGroup,
          label: storyHandleLabel(for: railGroup),
          isSelected: isSelected
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isSelected ? "Current story" : "Switch story")
    } else {
      Color.clear
    }
  }

  private func storyRailNeighbor(offset: Int) -> MIRAStoryGroup? {
    let groups = storyRailGroups
    guard let index = groups.firstIndex(where: { $0.userId == activeGroup.userId }) else { return nil }
    let neighborIndex = index + offset
    guard groups.indices.contains(neighborIndex) else { return nil }
    return groups[neighborIndex]
  }

  @MainActor
  private func prewarmStoryMediaWindow() async {
    let urls = storyMediaWindowURLs()
    guard !urls.isEmpty else { return }
    MIRAVideoPrewarmManager.shared.prewarm(urls: urls, keepOnly: Set(urls.prefix(3)))
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 1920, limit: 10)
    }
  }

  private func storyMediaWindowURLs() -> [String] {
    var urls: [String] = []

    let lower = max(0, selectedIndex - 1)
    let upper = min(stories.count - 1, selectedIndex + 5)
    if lower <= upper {
      for index in lower...upper {
        if let url = stories[index].mediaURL {
          urls.append(url)
        }
      }
    }

    let groups = storyRailGroups
    if let groupIndex = groups.firstIndex(where: { $0.userId == activeGroup.userId }) {
      for offset in [-1, 1, 2, 3, 4, 5] {
        let nextIndex = groupIndex + offset
        guard groups.indices.contains(nextIndex) else { continue }
        urls.append(contentsOf: (groups[nextIndex].statuses ?? []).prefix(5).compactMap(\.mediaURL))
      }
    }

    return orderedUniqueStoryURLs(urls)
  }

  private func prewarmStoriesStarting(at index: Int) {
    guard stories.indices.contains(index) else { return }
    let upper = min(stories.count - 1, index + 5)
    let urls = orderedUniqueStoryURLs((index...upper).compactMap { stories[$0].mediaURL })
    guard !urls.isEmpty else { return }
    MIRAVideoPrewarmManager.shared.prewarm(urls: urls, keepOnly: Set(urls.prefix(2)))
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 1920, limit: 6)
    }
  }

  private func orderedUniqueStoryURLs(_ urls: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for url in urls {
      let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      result.append(trimmed)
    }
    return result
  }

  private func storyHandleLabel(for railGroup: MIRAStoryGroup) -> String {
    if MIRAUsernameRules.isValidPublicUsername(railGroup.userUsername) {
      return "@\(MIRAUsernameRules.normalized(railGroup.userUsername))"
    }
    return railGroup.displayName
  }

  private func selectStoryGroup(_ railGroup: MIRAStoryGroup) {
    let urls = orderedUniqueStoryURLs((railGroup.statuses ?? []).prefix(5).compactMap(\.mediaURL))
    if !urls.isEmpty {
      MIRAVideoPrewarmManager.shared.prewarm(urls: urls, keepOnly: Set(urls.prefix(2)))
      Task.detached(priority: .utility) {
        await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 1920, limit: 5)
      }
    }
    withAnimation(storyRailAnimation) {
      activeGroupOverride = railGroup
      localStories = railGroup.statuses ?? []
      selectedIndex = 0
      visibleThoughts.removeAll()
      thoughtErrorText = nil
    }
  }

  private func handleStoryGroupSwipe(_ value: DragGesture.Value) {
    let horizontal = value.translation.width
    let vertical = value.translation.height
    guard abs(horizontal) > 44, abs(horizontal) > abs(vertical) * 1.35 else { return }
    if horizontal < 0 {
      goToNextStoryGroup()
    } else {
      goToPreviousStoryGroup()
    }
  }

  private func goToNextStoryGroup() {
    switchStoryGroup(offset: 1)
  }

  private func goToPreviousStoryGroup() {
    switchStoryGroup(offset: -1)
  }

  private func switchStoryGroup(offset: Int) {
    let groups = storyRailGroups
    guard let currentIndex = groups.firstIndex(where: { $0.userId == activeGroup.userId }) else { return }
    let nextIndex = currentIndex + offset
    guard groups.indices.contains(nextIndex) else { return }
    selectStoryGroup(groups[nextIndex])
  }

  private var storyTopBar: some View {
    HStack(spacing: 11) {
      RemoteAvatar(url: activeGroup.userProfileImage, size: 36)

      HStack(spacing: 7) {
        Text(activeGroup.displayName)
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

      Button { showStoryMenu = true } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 23, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
      }
      .buttonStyle(.miraPress)
      .padding(.trailing, 8)

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
        TextField("Share thought", text: $replyText)
          .font(.system(size: 16, weight: .regular))
          .foregroundStyle(.white)
          .tint(.white)
          .focused($isReplyFocused)
          .submitLabel(.send)
          .onSubmit(sendStoryThought)

        Spacer(minLength: 4)

        if isSendingThought {
          ProgressView()
            .tint(.white)
            .scaleEffect(0.72)
            .frame(width: 30, height: 30)
        } else if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Button(action: sendStoryThought) {
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

      Button { toggleStoryLike() } label: {
        Image(systemName: currentStory?.viewerLiked == true ? "heart.fill" : "heart")
          .font(.system(size: 29, weight: .regular))
          .foregroundStyle(currentStory?.viewerLiked == true ? MIRATheme.Color.like : .white)
          .frame(width: 38, height: 48)
          .scaleEffect(currentStory?.viewerLiked == true ? 1.06 : 1)
      }
      .disabled(isSubmittingStoryLike || currentStory == nil)
      .buttonStyle(.miraPress)
    }
    .overlay(alignment: .topLeading) {
      if let thoughtErrorText {
        Text(thoughtErrorText)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.black.opacity(0.42), in: Capsule())
          .offset(x: 4, y: -34)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
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
  private func loadStoryThoughtsForCurrentStory() async {
    thoughtPlaybackTask?.cancel()
    visibleThoughts.removeAll()
    thoughtErrorText = nil
    guard let storyId = currentStory?.id else {
      storyThoughts = []
      return
    }

    do {
      let loaded: [StoryThought] = try await api.get("/statuses/\(storyId)/thoughts")
      storyThoughts = loaded.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      startStoryThoughtPlayback()
    } catch {
      storyThoughts = []
    }
  }

  @MainActor
  private func startStoryThoughtPlayback() {
    thoughtPlaybackTask?.cancel()
    let queuedThoughts = Array(storyThoughts.suffix(10))
    guard !queuedThoughts.isEmpty else { return }

    thoughtPlaybackTask = Task {
      try? await Task.sleep(nanoseconds: 500_000_000)
      for thought in queuedThoughts {
        if Task.isCancelled { return }
        await MainActor.run { showStoryThought(thought) }
        try? await Task.sleep(nanoseconds: 1_650_000_000)
      }
    }
  }

  @MainActor
  private func showStoryThought(_ thought: StoryThought) {
    let bubble = StoryThoughtBubbleState(thought: thought)
    withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
      visibleThoughts.append(bubble)
      if visibleThoughts.count > 3 {
        visibleThoughts.removeFirst(visibleThoughts.count - 3)
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
      Task { @MainActor in
        withAnimation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion)) {
          visibleThoughts.removeAll { $0.id == bubble.id }
        }
      }
    }
  }

  @MainActor
  private func sendStoryThought() {
    let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isSendingThought, let storyId = currentStory?.id else { return }
    isSendingThought = true
    thoughtErrorText = nil

    Task {
      do {
        let thought: StoryThought = try await api.post(
          "/statuses/\(storyId)/thoughts",
          body: StoryThoughtSubmitBody(body: text)
        )
        await MainActor.run {
          replyText = ""
          isReplyFocused = false
          isSendingThought = false
          storyThoughts.append(thought)
          showStoryThought(thought)
          CaptroHaptics.light()
        }
      } catch {
        await MainActor.run {
          isSendingThought = false
          thoughtErrorText = "Could not share thought."
          CaptroHaptics.warning()
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            Task { @MainActor in
              withAnimation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion)) {
                thoughtErrorText = nil
              }
            }
          }
        }
      }
    }
  }

  @MainActor
  private func toggleStoryLike() {
    guard !isSubmittingStoryLike, let story = currentStory else { return }
    let nextLiked = !story.viewerLiked
    let nextCount = max(0, (story.likesCount ?? 0) + (nextLiked ? 1 : -1))
    updateCurrentStory(liked: nextLiked, likesCount: nextCount)
    isSubmittingStoryLike = true
    CaptroHaptics.light()

    Task {
      do {
        let response: PostLikeResponse = try await api.post("/statuses/\(story.id)/like", body: LikeBody(liked: nextLiked))
        await MainActor.run {
          updateCurrentStory(
            liked: response.liked ?? nextLiked,
            likesCount: response.likesCount ?? nextCount
          )
          isSubmittingStoryLike = false
        }
      } catch {
        await MainActor.run {
          updateCurrentStory(liked: story.viewerLiked, likesCount: story.likesCount ?? 0)
          isSubmittingStoryLike = false
          CaptroHaptics.warning()
        }
      }
    }
  }

  @MainActor
  private func updateCurrentStory(liked: Bool, likesCount: Int) {
    guard stories.indices.contains(selectedIndex) else { return }
    var updatedStories = stories
    updatedStories[selectedIndex] = updatedStories[selectedIndex].updating(liked: liked, likesCount: likesCount)
    localStories = updatedStories
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
        withAnimation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion)) {
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
        ownerUserId: story.userId ?? activeGroup.userId,
        title: "Report story",
        subtitle: story.content?.isEmpty == false ? story.content : activeGroup.displayName
      )
    )
  }

  private func blockStoryOwner() async {
    let ownerId = currentStory?.userId ?? activeGroup.userId
    guard !ownerId.isEmpty, ownerId != currentUserId else { return }
    let _: EmptyResponse? = try? await api.post("/users/\(ownerId)/block", body: EmptyBody())
    closeStoryViewer()
  }

  private func closeStoryViewer() {
    guard !isClosing else { return }
    isClosing = true
    MIRAApplePerformanceLogger.event("story_viewer_close")
    let duration = reduceMotion ? CaptroMotion.Duration.reduced : CaptroMotion.Duration.fullScreenClose
    withAnimation(CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)) {
      isCanvasVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
      onClose()
    }
  }

  private func goToPreviousStory() {
    if selectedIndex > 0 {
      prewarmStoriesStarting(at: selectedIndex - 1)
      withAnimation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion)) {
        selectedIndex -= 1
      }
    }
  }

  private func goToNextStory() {
    guard selectedIndex < stories.count - 1 else {
      return
    }
    prewarmStoriesStarting(at: selectedIndex + 1)
    withAnimation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion)) {
      selectedIndex += 1
    }
  }
}

private struct StoryThoughtBubbleView: View {
  let thought: StoryThought

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      RemoteAvatar(url: thought.userProfileImage, size: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(thought.displayName)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white.opacity(0.82))
          .lineLimit(1)
        Text(thought.body)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: 260, alignment: .leading)
    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 17, style: .continuous)
        .stroke(.white.opacity(0.08), lineWidth: 1)
    )
  }
}

private struct StoryTopRoundedRectangle: Shape {
  let radius: CGFloat

  func path(in rect: CGRect) -> Path {
    let r = min(radius, min(rect.width, rect.height) / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + r, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + r),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

private struct StoryViewerCarouselBubble: View {
  let group: MIRAStoryGroup
  let label: String
  let isSelected: Bool

  private var bubbleSize: CGFloat { isSelected ? 72 : 50 }
  private var previewStory: MIRAStatusPreview? { group.statuses?.first }

  var body: some View {
    VStack(spacing: 7) {
      ZStack {
        Circle()
          .stroke(
            isSelected
              ? LinearGradient(colors: [Color.pink, Color.purple, MIRATheme.Color.forest], startPoint: .topLeading, endPoint: .bottomTrailing)
              : LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: isSelected ? 3 : 1
          )
          .frame(width: bubbleSize + 8, height: bubbleSize + 8)

        if let mediaURL = previewStory?.mediaURL {
          RemoteMediaView(
            url: mediaURL,
            isVideo: mediaURL.isVideoURL,
            contentMode: .fill,
            shouldPlay: false,
            placeholderColor: MIRATheme.Color.mediaPlaceholder,
            placeholderTint: .white.opacity(0.55)
          )
          .frame(width: bubbleSize, height: bubbleSize)
          .clipShape(Circle())
        } else {
          RemoteAvatar(url: group.userProfileImage, size: bubbleSize)
        }

        if previewStory?.hasAudio == true {
          Circle()
            .fill(.white.opacity(0.88))
            .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
            .overlay(
              Image(systemName: "music.note")
                .font(.system(size: isSelected ? 10 : 8, weight: .bold))
                .foregroundStyle(MIRATheme.Color.forest)
            )
            .offset(x: bubbleSize * 0.35, y: -bubbleSize * 0.32)
        }
      }

      Text(label)
        .font(.system(size: isSelected ? 13 : 11, weight: .semibold))
        .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.64))
        .lineLimit(1)
        .frame(width: isSelected ? 104 : 72)
    }
    .frame(width: isSelected ? 116 : 76, height: 108, alignment: .bottom)
    .animation(CaptroMotion.mediaFadeAnimation(reduceMotion: false), value: isSelected)
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
        if let media = displayMediaURL {
          RemoteMediaView(
            url: media,
            isVideo: media.isVideoURL,
            placeholderURL: placeholderURL,
            fallbackURL: fallbackURL(for: media),
            shouldPlay: false,
            maxPixelSize: 560,
            showsVideoPlaceholderIcon: sourceIsVideo
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

        if carouselCount > 1 {
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

  private var displayMediaURL: String? {
    orderedMediaCandidates.first
  }

  private var placeholderURL: String? {
    let candidate = (post.posterMediaURLs + post.thumbnailMediaURLs)
      .map(cleanMediaURL)
      .first { !$0.isEmpty && $0 != displayMediaURL }
    return candidate
  }

  private var orderedMediaCandidates: [String] {
    let preferredPreview = post.posterMediaURLs + post.thumbnailMediaURLs
    let renderableFeed = post.feedMediaURLs.filter { !($0.isVideoURL && !sourceIsVideo) }
    return uniqueMediaURLs(preferredPreview + renderableFeed + post.mediaURLs)
  }

  private var sourceIsVideo: Bool {
    let types = post.mediaTypes?.values.map { $0.lowercased() } ?? []
    return types.contains { $0.contains("video") }
      || post.feedMediaURLs.contains { $0.isVideoURL }
      || post.mediaURLs.contains { $0.isVideoURL }
  }

  private var carouselCount: Int {
    max(post.feedMediaURLs.count, post.mediaURLs.count, post.thumbnailMediaURLs.count, post.posterMediaURLs.count)
  }

  private func fallbackURL(for media: String) -> String? {
    uniqueMediaURLs(post.feedMediaURLs + post.mediaURLs)
      .first { $0 != media && !$0.isVideoURL }
  }

  private func uniqueMediaURLs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values
      .map(cleanMediaURL)
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  private func cleanMediaURL(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
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
