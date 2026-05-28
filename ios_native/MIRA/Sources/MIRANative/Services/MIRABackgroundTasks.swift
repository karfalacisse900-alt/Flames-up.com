import BackgroundTasks
import Foundation

public enum MIRABackgroundTaskIdentifiers {
  public static let appRefresh = "com.karfala90.frontend.background-refresh"
  public static let cacheCleanup = "com.karfala90.frontend.cache-cleanup"
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
    async let chat: Bool = refreshChat(api: api)
    await cleanupCaches()
    let feedUpdated = await feed
    let discoverUpdated = await discover
    let chatUpdated = await chat
    let result = feedUpdated || discoverUpdated || chatUpdated
    MIRAApplePerformanceLogger.event("background_refresh_complete", detail: result ? "updated" : "no_update")
    return result
  }

  static func cleanupCaches() async {
    await MIRALocalJSONCache.trim()
    await MIRAImageDiskCache.trim()
    MIRAApplePerformanceLogger.event("background_cache_cleanup_complete")
  }

  private static func refreshFeed(api: MIRAAPIClient) async -> Bool {
    guard let posts: [MIRAPost] = try? await api.get("/posts/feed?limit=8"), !posts.isEmpty else { return false }
    await MIRALocalJSONCache.save(posts, key: "native.main.feed.v3")
    return true
  }

  private static func refreshDiscover(api: MIRAAPIClient) async -> Bool {
    guard let posts: [MIRAPost] = try? await api.get("/discover?category=all&limit=18"), !posts.isEmpty else { return false }
    await MIRALocalJSONCache.save(posts, key: "native.discover.posts.v3.all")
    return true
  }

  private static func refreshChat(api: MIRAAPIClient) async -> Bool {
    guard let conversations: [MIRAConversation] = try? await api.get("/conversations") else { return false }
    await MIRALocalJSONCache.save(conversations, key: "native.chat.conversations.v2")
    return true
  }
}
