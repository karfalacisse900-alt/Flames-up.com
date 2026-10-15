import Foundation
import Combine

/// A server-confirmed publication receipt, not a second feed or optimistic post.
struct CaptroPublishedPost: Equatable {
  let post: MIRAPost
  let accountScope: String
}

@MainActor
final class CaptroPublicationStore: ObservableObject {
  @Published private(set) var latest: CaptroPublishedPost?

  @discardableResult
  func record(_ post: MIRAPost, expectedScope: String) -> Bool {
    guard expectedScope == MIRALocalJSONCache.currentScopeIdentifier,
          !post.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    let receipt = CaptroPublishedPost(post: post.bindingWritingIdentities(), accountScope: expectedScope)
    if latest != receipt { latest = receipt }
    NotificationCenter.default.post(name: .captroPostSubmissionCompleted, object: receipt)
    return true
  }

  func clear() { latest = nil }

  func consume(_ receipt: CaptroPublishedPost) -> Bool {
    guard latest == receipt else { return false }
    latest = nil
    return true
  }
}

struct CaptroPublicationNotice: Equatable {
  enum State: Equatable { case checking, available, outsideFeed, retry }
  let receipt: CaptroPublishedPost
  var state: State
  var message: String {
    switch state {
    case .checking: return "Published · Checking Home"
    case .available: return "New post"
    case .outsideFeed: return "Published"
    case .retry: return "Published · Couldn't update Home"
    }
  }
}
