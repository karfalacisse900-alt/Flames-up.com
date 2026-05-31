import Foundation

public struct MIRAChatThreadSnapshot: Codable, Hashable {
  public let messages: [MIRAMessage]
  public let lastSyncedAt: String?
  public let lastServerSequence: Int?
  public let hasOlderRemote: Bool
  public let savedAt: String
}

public struct MIRAChatConversationsSnapshot: Codable, Hashable {
  public let conversations: [MIRAConversation]
  public let lastSyncedAt: String?
  public let savedAt: String
}

public struct MIRAChatMediaDownloadSettings: Codable, Hashable {
  public var autoDownloadImagesOnWiFi: Bool
  public var autoDownloadVideosOnWiFi: Bool
  public var autoDownloadFilesOnWiFi: Bool
  public var useCellularForMediaDownloads: Bool

  public static let defaults = MIRAChatMediaDownloadSettings(
    autoDownloadImagesOnWiFi: true,
    autoDownloadVideosOnWiFi: false,
    autoDownloadFilesOnWiFi: false,
    useCellularForMediaDownloads: false
  )
}

actor MIRAChatLocalStore {
  static let shared = MIRAChatLocalStore()

  private let maxThreadMessages = 320
  private let cacheMaxAge: TimeInterval = 60 * 60 * 24 * 90

  func loadConversations(userId: String) async -> MIRAChatConversationsSnapshot? {
    await MIRALocalJSONCache.load(
      MIRAChatConversationsSnapshot.self,
      key: conversationsKey(userId: userId),
      maxAge: cacheMaxAge
    )
  }

  func saveConversations(_ conversations: [MIRAConversation], userId: String) async {
    let snapshot = MIRAChatConversationsSnapshot(
      conversations: conversations,
      lastSyncedAt: nowISO(),
      savedAt: nowISO()
    )
    await MIRALocalJSONCache.save(snapshot, key: conversationsKey(userId: userId))
  }

  func loadThread(kind: ConversationNativeKind, currentUserId: String, limit: Int = 50) async -> MIRAChatThreadSnapshot? {
    guard let snapshot = await MIRALocalJSONCache.load(
      MIRAChatThreadSnapshot.self,
      key: threadKey(kind: kind, currentUserId: currentUserId),
      maxAge: cacheMaxAge
    ) else { return nil }

    let sorted = sortedMessages(snapshot.messages)
    let visible = limit > 0 ? Array(sorted.suffix(limit)) : sorted
    return MIRAChatThreadSnapshot(
      messages: visible,
      lastSyncedAt: snapshot.lastSyncedAt,
      lastServerSequence: snapshot.lastServerSequence,
      hasOlderRemote: snapshot.hasOlderRemote || sorted.count > visible.count,
      savedAt: snapshot.savedAt
    )
  }

  func saveThread(
    kind: ConversationNativeKind,
    currentUserId: String,
    messages: [MIRAMessage],
    lastSyncedAt: String?,
    lastServerSequence: Int?,
    hasOlderRemote: Bool
  ) async {
    let sorted = sortedMessages(dedupedMessages(messages))
    let trimmed = Array(sorted.suffix(maxThreadMessages))
    let latestCursor = lastSyncedAt ?? latestRemoteCursor(in: trimmed)
    let snapshot = MIRAChatThreadSnapshot(
      messages: trimmed,
      lastSyncedAt: latestCursor,
      lastServerSequence: lastServerSequence ?? trimmed.compactMap(\.serverSequence).max(),
      hasOlderRemote: hasOlderRemote || sorted.count > trimmed.count,
      savedAt: nowISO()
    )
    await MIRALocalJSONCache.save(snapshot, key: threadKey(kind: kind, currentUserId: currentUserId))
  }

  func merge(_ existing: [MIRAMessage], with incoming: [MIRAMessage]) -> [MIRAMessage] {
    sortedMessages(dedupedMessages(existing + incoming))
  }

  func loadDownloadSettings() async -> MIRAChatMediaDownloadSettings {
    await MIRALocalJSONCache.load(
      MIRAChatMediaDownloadSettings.self,
      key: "native.chat.media.download.settings.v1",
      maxAge: cacheMaxAge
    ) ?? .defaults
  }

  func saveDownloadSettings(_ settings: MIRAChatMediaDownloadSettings) async {
    await MIRALocalJSONCache.save(settings, key: "native.chat.media.download.settings.v1")
  }

  func storeOutgoingMedia(data: Data, fileName: String) async -> URL? {
    await Task.detached(priority: .utility) {
      guard let directory = chatMediaDirectory() else { return nil }
      let safeName = fileName
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
      let url = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
      do {
        try data.write(to: url, options: [.atomic])
        return url
      } catch {
        return nil
      }
    }.value
  }

  private func conversationsKey(userId: String) -> String {
    "native.chat.conversations.local.v1.\(userId.isEmpty ? "anonymous" : userId)"
  }

  private func threadKey(kind: ConversationNativeKind, currentUserId: String) -> String {
    switch kind {
    case let .direct(peerId):
      return "native.chat.thread.local.v1.\(currentUserId.isEmpty ? "anonymous" : currentUserId).direct.\(peerId)"
    case let .group(groupId):
      return "native.chat.thread.local.v1.group.\(groupId)"
    }
  }

  private func latestRemoteCursor(in messages: [MIRAMessage]) -> String? {
    messages
      .filter { !($0.id.hasPrefix("local-")) }
      .compactMap(\.createdAt)
      .max { lhs, rhs in dateValue(lhs) < dateValue(rhs) }
  }

  private func dedupedMessages(_ messages: [MIRAMessage]) -> [MIRAMessage] {
    var byId: [String: MIRAMessage] = [:]
    for message in messages {
      if let existing = byId[message.id] {
        byId[message.id] = message.updating(localCreatedAt: existing.localCreatedAt)
      } else {
        byId[message.id] = message
      }
    }
    return Array(byId.values)
  }

  private func sortedMessages(_ messages: [MIRAMessage]) -> [MIRAMessage] {
    messages.sorted { lhs, rhs in
      if let lhsSequence = lhs.serverSequence, let rhsSequence = rhs.serverSequence, lhsSequence != rhsSequence {
        return lhsSequence < rhsSequence
      }
      let left = sortDate(lhs)
      let right = sortDate(rhs)
      if left == right {
        return lhs.id < rhs.id
      }
      return left < right
    }
  }

  private func sortDate(_ message: MIRAMessage) -> Date {
    let status = message.status?.lowercased() ?? ""
    let shouldUseLocalDate = message.id.hasPrefix("local-") || status == "sending" || status == "failed"
    if shouldUseLocalDate, let localCreatedAt = message.localCreatedAt {
      return dateValue(localCreatedAt)
    }
    if let createdAt = message.createdAt {
      return dateValue(createdAt)
    }
    if let localCreatedAt = message.localCreatedAt {
      return dateValue(localCreatedAt)
    }
    return .distantPast
  }

  private func dateValue(_ value: String) -> Date {
    if let date = ISO8601DateFormatter.miraChatFractional.date(from: value) { return date }
    if let date = ISO8601DateFormatter.miraChat.date(from: value) { return date }
    return .distantPast
  }

  private func nowISO() -> String {
    ISO8601DateFormatter.miraChatFractional.string(from: Date())
  }
}

private extension ISO8601DateFormatter {
  static let miraChat: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  static let miraChatFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

private func chatMediaDirectory() -> URL? {
  guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
  let directory = caches.appendingPathComponent("MIRAChatMedia", isDirectory: true)
  if !FileManager.default.fileExists(atPath: directory.path) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  return directory
}
