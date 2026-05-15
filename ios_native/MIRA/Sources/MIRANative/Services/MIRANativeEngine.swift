import Foundation
import MIRACoreCpp

public struct MIRANativeMediaPlan: Decodable, Sendable {
  public let kind: String
  public let allowed: Bool
  public let reason: String
  public let targetWidth: Int
  public let targetHeight: Int
  public let aspectRatio: Double
  public let maxBytes: Int
  public let targetMimeType: String
  public let imageQuality: Double
  public let videoBitrate: Int
  public let targetFps: Int
  public let shouldUseThumbnail: Bool
  public let cacheKey: String
}

public struct MIRANativeDesignProfile: Decodable, Sendable {
  public let runtime: String
  public let platform: String
  public let surface: String
  public let surfaceSoft: String
  public let textPrimary: String
  public let textSecondary: String
  public let forest: String
  public let forestPressed: String
  public let shadowColor: String
  public let shadowOpacity: Double
  public let radiusCard: Double
  public let radiusSheet: Double
  public let minTouchTarget: Double
}

public enum MIRANativeEngine {
  private static let decoder = JSONDecoder()

  public static func planMedia(
    uri: String,
    mimeType: String,
    fileName: String,
    fileSize: Double,
    width: Double,
    height: Double,
    preset: String = "quality"
  ) -> MIRANativeMediaPlan {
    let json = uri.withCString { uriPointer in
      mimeType.withCString { mimePointer in
        fileName.withCString { filePointer in
          preset.withCString { presetPointer in
            let raw = mira_plan_media_json(uriPointer, mimePointer, filePointer, fileSize, width, height, presetPointer)
            return raw.map { String(cString: $0) } ?? ""
          }
        }
      }
    }
    if let data = json.data(using: .utf8),
       let plan = try? decoder.decode(MIRANativeMediaPlan.self, from: data) {
      return plan
    }
    return MIRANativeMediaPlan(
      kind: "unknown",
      allowed: false,
      reason: "native_media_plan_failed",
      targetWidth: 0,
      targetHeight: 0,
      aspectRatio: 0.75,
      maxBytes: 0,
      targetMimeType: "image/jpeg",
      imageQuality: 0.89,
      videoBitrate: 8_000_000,
      targetFps: 30,
      shouldUseThumbnail: false,
      cacheKey: "missing"
    )
  }

  public static func scoreFeedItem(
    likes: Double,
    comments: Double,
    saves: Double,
    shares: Double,
    views: Double,
    ageHours: Double,
    isFollowed: Bool,
    isVideo: Bool
  ) -> Double {
    mira_score_feed_item(
      likes,
      comments,
      saves,
      shares,
      views,
      ageHours,
      isFollowed ? 1 : 0,
      isVideo ? 1 : 0
    )
  }

  public static func stableHash(_ value: String) -> UInt64 {
    value.withCString { mira_stable_hash64($0) }
  }

  public static var designProfile: MIRANativeDesignProfile {
    let raw = mira_native_design_profile_json()
    let json = raw.map { String(cString: $0) } ?? ""
    if let data = json.data(using: .utf8),
       let profile = try? decoder.decode(MIRANativeDesignProfile.self, from: data) {
      return profile
    }
    return MIRANativeDesignProfile(
      runtime: "swift",
      platform: "ios",
      surface: "#FFFFFF",
      surfaceSoft: "#FAFAF8",
      textPrimary: "#1D2119",
      textSecondary: "#687066",
      forest: "#20361F",
      forestPressed: "#172917",
      shadowColor: "#20361F",
      shadowOpacity: 0.10,
      radiusCard: 22,
      radiusSheet: 28,
      minTouchTarget: 44
    )
  }
}
