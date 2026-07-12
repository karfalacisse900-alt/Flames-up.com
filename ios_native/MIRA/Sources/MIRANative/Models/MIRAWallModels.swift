import CoreGraphics
import Foundation

public enum MIRAWallDestination: String, CaseIterable, Codable, Identifiable {
  case global
  case nearby
  case newYorkCity = "new_york_city"
  case brooklyn
  case upperManhattan = "upper_manhattan"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .global: "Global"
    case .nearby: "Nearby"
    case .newYorkCity: "New York City"
    case .brooklyn: "Brooklyn"
    case .upperManhattan: "Upper Manhattan"
    }
  }

  public var subtitle: String {
    switch self {
    case .global: "Notes from across Captro"
    case .nearby: "Your broad local area"
    case .newYorkCity: "Across New York City"
    case .brooklyn: "Brooklyn wall"
    case .upperManhattan: "Upper Manhattan wall"
    }
  }

  public var systemImage: String {
    switch self {
    case .global: "globe.americas.fill"
    case .nearby: "location.fill"
    case .newYorkCity: "building.2.fill"
    case .brooklyn: "building.columns.fill"
    case .upperManhattan: "building.fill"
    }
  }
}

public struct MIRAWallOverview: Decodable, Equatable {
  public let wallId: String
  public let displayName: String
  public let totalCount: Int
  public let minX: Double?
  public let maxX: Double?
  public let minY: Double?
  public let maxY: Double?

  public var noteBounds: CGRect? {
    guard totalCount > 0,
          let minX, let maxX, let minY, let maxY,
          maxX > minX, maxY > minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}

public struct MIRAWallAuthorPreview: Codable, Hashable {
  public let userId: String?
  public let username: String?
  public let displayName: String?
  public let avatarUrl: String?

  public var title: String {
    let cleanUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cleanUsername.isEmpty { return "@\(cleanUsername)" }
    let cleanName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleanName.isEmpty ? "Captro member" : cleanName
  }
}

public struct MIRAWallNote: Codable, Identifiable, Hashable {
  public let id: String
  public let wallId: String
  public let publishingIdentity: String
  public let body: String
  public let category: String?
  public let colorToken: String
  public let styleToken: String
  public let worldX: Double
  public let worldY: Double
  public let width: Double
  public let height: Double
  public let rotation: Double
  public let zIndex: Int
  public let approximateLocation: String?
  public let createdAt: String
  public let updatedAt: String?
  public let saveCount: Int
  public let reactionCount: Int
  public let replyCount: Int
  public let reactedByViewer: Bool
  public let savedByViewer: Bool
  public let authorPreview: MIRAWallAuthorPreview?

  public var isGhost: Bool { publishingIdentity.lowercased() == "ghost" }

  public func updating(
    reacted: Bool? = nil,
    reactionCount: Int? = nil,
    saved: Bool? = nil,
    saveCount: Int? = nil,
    replyCount: Int? = nil
  ) -> MIRAWallNote {
    MIRAWallNote(
      id: id,
      wallId: wallId,
      publishingIdentity: publishingIdentity,
      body: body,
      category: category,
      colorToken: colorToken,
      styleToken: styleToken,
      worldX: worldX,
      worldY: worldY,
      width: width,
      height: height,
      rotation: rotation,
      zIndex: zIndex,
      approximateLocation: approximateLocation,
      createdAt: createdAt,
      updatedAt: updatedAt,
      saveCount: saveCount ?? self.saveCount,
      reactionCount: reactionCount ?? self.reactionCount,
      replyCount: replyCount ?? self.replyCount,
      reactedByViewer: reacted ?? reactedByViewer,
      savedByViewer: saved ?? savedByViewer,
      authorPreview: authorPreview
    )
  }
}

public struct MIRAWallNotesResponse: Decodable {
  public let notes: [MIRAWallNote]
  public let wallId: String?
  public let zoom: Double?
}

public struct MIRAWallNoteResponse: Decodable {
  public let note: MIRAWallNote
}

public struct MIRAWallToggleResponse: Decodable {
  public let reacted: Bool?
  public let reactionCount: Int?
  public let saved: Bool?
  public let saveCount: Int?
}

public struct MIRAWallReply: Codable, Identifiable, Hashable {
  public let id: String
  public let noteId: String
  public let body: String
  public let publishingIdentity: String
  public let createdAt: String
  public let authorPreview: MIRAWallAuthorPreview?

  public var isGhost: Bool { publishingIdentity.lowercased() == "ghost" }
}

public struct MIRAWallRepliesResponse: Decodable {
  public let replies: [MIRAWallReply]
}

public struct MIRAWallReplyResponse: Decodable {
  public let reply: MIRAWallReply
  public let replyCount: Int?
}

public struct MIRACreateWallNoteBody: Encodable {
  public let wallId: String
  public let publishingIdentity: String
  public let body: String
  public let category: String?
  public let colorToken: String
  public let styleToken: String
  public let worldX: Double
  public let worldY: Double
  public let width: Double
  public let height: Double
  public let rotation: Double
  public let approximateLocation: String?
}

public struct MIRAWallReactionBody: Encodable {
  public let reacted: Bool
}

public struct MIRAWallSaveBody: Encodable {
  public let saved: Bool
}

public struct MIRAWallReplyBody: Encodable {
  public let body: String
  public let publishingIdentity: String
}
