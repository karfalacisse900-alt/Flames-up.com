import BackgroundTasks
import Foundation

public enum MIRABackgroundTaskIdentifiers {
  public static let appRefresh = "com.captro.app.background-refresh"
  public static let cacheCleanup = "com.captro.app.cache-cleanup"
}

public final class MIRABackgroundTaskCoordinator {
  public static let shared = MIRABackgroundTaskCoordinator()

  private var didRegister = false

  private init() {}

  public func register() {
    guard !didRegister else { return }
    didRegister = true
    BGTaskScheduler.shared.register(forTaskWithIdentifier: MIRABackgroundTaskIdentifiers.appRefresh, using: nil) { task in
      self.handleAppRefresh(task)
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: MIRABackgroundTaskIdentifiers.cacheCleanup, using: nil) { task in
      self.handleCacheCleanup(task)
    }
    MIRAApplePerformanceLogger.event("background_tasks_registered")
  }

  public func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: MIRABackgroundTaskIdentifiers.appRefresh)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 25 * 60)
    do {
      try BGTaskScheduler.shared.submit(request)
      MIRAApplePerformanceLogger.event("background_refresh_scheduled")
    } catch {
      MIRAApplePerformanceLogger.event("background_refresh_schedule_failed")
    }
  }

  public func scheduleCacheCleanup() {
    let request = BGAppRefreshTaskRequest(identifier: MIRABackgroundTaskIdentifiers.cacheCleanup)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    do {
      try BGTaskScheduler.shared.submit(request)
      MIRAApplePerformanceLogger.event("background_cache_cleanup_scheduled")
    } catch {
      MIRAApplePerformanceLogger.event("background_cache_cleanup_schedule_failed")
    }
  }

  private func handleAppRefresh(_ task: BGTask) {
    scheduleAppRefresh()
    let operation = Task.detached(priority: .utility) {
      await MIRABackgroundRefreshWorker.refreshCaches()
    }
    task.expirationHandler = {
      operation.cancel()
    }
    Task {
      let success = await operation.value
      task.setTaskCompleted(success: success)
    }
  }

  private func handleCacheCleanup(_ task: BGTask) {
    scheduleCacheCleanup()
    let operation = Task.detached(priority: .utility) {
      await MIRABackgroundRefreshWorker.cleanupCaches()
      return true
    }
    task.expirationHandler = {
      operation.cancel()
    }
    Task {
      let success = await operation.value
      task.setTaskCompleted(success: success)
    }
  }
}

private enum MIRABackgroundRefreshWorker {
  static func refreshCaches() async -> Bool {
    MIRAApplePerformanceLogger.event("background_refresh_start")
    let keychain = MIRAKeychainSessionProvider()
    guard await keychain.accessToken() != nil else {
      await cleanupCaches()
      MIRAApplePerformanceLogger.event("background_refresh_skip", detail: "signed_out")
      return true
    }

    let api = MIRAAPIClient(sessionProvider: keychain)
    async let feed: Bool = refreshFeed(api: api)
    async let discover: Bool = refreshDiscover(api: api)
    async let profile: Bool = refreshProfile(api: api)
    async let notifications: Bool = refreshNotifications(api: api)
    async let chat: Bool = refreshChat(api: api)
    await cleanupCaches()
    let feedUpdated = await feed
    let discoverUpdated = await discover
    let profileUpdated = await profile
    let notificationsUpdated = await notifications
    let chatUpdated = await chat
    let result = feedUpdated || discoverUpdated || profileUpdated || notificationsUpdated || chatUpdated
    MIRAApplePerformanceLogger.event("background_refresh_complete", detail: result ? "updated" : "no_update")
    return result
  }

  static func cleanupCaches() async {
    await MIRAAppCacheStore.shared.cleanup()
    MIRAApplePerformanceLogger.event("background_cache_cleanup_complete")
  }

  private static func refreshFeed(api: MIRAAPIClient) async -> Bool {
    guard let posts: [MIRAPost] = try? await api.get("/posts/feed?limit=8"), !posts.isEmpty else { return false }
    let cached = await MIRAAppCacheStore.shared.loadFeed() ?? []
    let merged = await MIRAAppCacheStore.shared.mergeFreshFirstPage(existing: cached, fresh: posts, pageLimit: 8)
    await MIRAAppCacheStore.shared.saveFeed(merged)
    return true
  }

  private static func refreshDiscover(api: MIRAAPIClient) async -> Bool {
    guard let posts: [MIRAPost] = try? await api.get("/discover?category=all&limit=18"), !posts.isEmpty else { return false }
    let cached = await MIRAAppCacheStore.shared.loadDiscoverPosts(category: "all") ?? []
    let merged = await MIRAAppCacheStore.shared.mergeFreshPostsPreservingViewerState(existing: cached, fresh: posts, maxCount: 90)
    await MIRAAppCacheStore.shared.saveDiscoverPosts(merged, category: "all")
    return true
  }

  private static func refreshProfile(api: MIRAAPIClient) async -> Bool {
    guard let user: MIRAUser = try? await api.get("/auth/me") else { return false }
    await MIRAAppCacheStore.shared.saveCurrentProfile(user)
    if let posts: [MIRAPost] = try? await api.get("/users/\(user.id)/posts") {
      let cached = await MIRAAppCacheStore.shared.loadProfilePosts(userId: user.id) ?? []
      let merged = await MIRAAppCacheStore.shared.mergeFreshPostsPreservingViewerState(existing: cached, fresh: posts, maxCount: 120)
      await MIRAAppCacheStore.shared.saveProfilePosts(merged, userId: user.id)
    }
    return true
  }

  private static func refreshNotifications(api: MIRAAPIClient) async -> Bool {
    guard let notifications: [MIRANotification] = try? await api.get("/notifications?limit=60") else { return false }
    await MIRAAppCacheStore.shared.saveNotifications(notifications)
    return true
  }

  private static func refreshChat(api: MIRAAPIClient) async -> Bool {
    guard let conversations: [MIRAConversation] = try? await api.get("/conversations") else { return false }
    if let user: MIRAUser = try? await api.get("/auth/me") {
      await MIRAChatLocalStore.shared.saveConversations(conversations, userId: user.id)
    }
    return true
  }
}
