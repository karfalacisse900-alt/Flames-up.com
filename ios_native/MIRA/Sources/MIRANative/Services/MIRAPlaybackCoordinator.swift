import Foundation

public enum MIRAPlaybackCoordinator {
  public static func pauseAll(reason: String) {
    NotificationCenter.default.post(name: .miraPlaybackShouldPause, object: reason)
  }

  public static func resumeVisible(reason: String) {
    NotificationCenter.default.post(name: .miraPlaybackMayResume, object: reason)
  }
}

public extension Notification.Name {
  static let miraPlaybackShouldPause = Notification.Name("mira.playback.pauseAll")
  static let miraPlaybackMayResume = Notification.Name("mira.playback.resumeVisible")
}
