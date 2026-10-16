import Foundation

/// Cache age is not Story lifetime. Missing or malformed expiry is not permission
/// to display indefinitely. The clock is explicit for offline/foreground tests.
enum CaptroStoryExpiry {
  static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
  static func active(_ stories: [MIRAStatusPreview], at now: Date) -> [MIRAStatusPreview] {
    stories.filter { date($0.expiresAt).map { $0 > now } ?? false }
  }
  static func groups(_ groups: [MIRAStoryGroup], at now: Date) -> [MIRAStoryGroup] {
    groups.compactMap { group in
      let statuses = active(group.statuses ?? [], at: now)
      guard !statuses.isEmpty else { return nil }
      return MIRAStoryGroup(userId: group.userId, userUsername: group.userUsername,
        userFullName: group.userFullName, userProfileImage: group.userProfileImage,
        hasUnviewed: group.hasUnviewed, ownerType: group.ownerType, clubId: group.clubId, statuses: statuses, cacheGroupID: group.id)
    }
  }
  static func next(_ groups: [MIRAStoryGroup]) -> Date? {
    groups.flatMap { $0.statuses ?? [] }.compactMap { date($0.expiresAt) }.min()
  }
}
