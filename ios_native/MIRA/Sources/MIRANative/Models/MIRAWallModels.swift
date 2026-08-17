import CoreGraphics
import Foundation

public enum MIRAWallDestination: String, CaseIterable, Codable, Identifiable {
  case global

  public var id: String { rawValue }

  public var title: String {
    "Global"
  }

  public var subtitle: String {
    "Notes from across Captro"
  }

  public var systemImage: String {
    "globe.americas.fill"
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
  public let mediaUrl: String?
  public let mediaThumbnailUrl: String?
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

  public var noteType: String? = nil
  public var backBody: String? = nil
  public var backColorToken: String? = nil
  public var backStyleToken: String? = nil
  public var hasBackSide: Bool? = nil
  public var allowContributions: Bool? = nil
  public var signatureCount: Int? = nil
  public var contributionCount: Int? = nil
  public var signedByViewer: Bool? = nil
  public var viewerIsAuthor: Bool? = nil
  public var voice: MIRAWallVoiceMetadata? = nil
  public var location: MIRAWallLocationPreview? = nil
  public var document: MIRANoteDocument? = nil
  public var canvas: MIRANoteCanvas? = nil

  public var isGhost: Bool { publishingIdentity.lowercased() == "ghost" }
  public var isVoiceNote: Bool { noteType == "voice" || voice != nil }
  public var resolvedDocument: MIRANoteDocument? {
    if let document { return document }
    guard !isVoiceNote else { return nil }
    return MIRANoteDocument.legacyDocument(for: self)
  }
  public var resolvedCanvas: MIRANoteCanvas? {
    resolvedDocument?.canvas
  }
  public var canFlip: Bool {
    let cleanBack = backBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !cleanBack.isEmpty && hasBackSide != false
  }
  public var resolvedSignatureCount: Int { max(0, signatureCount ?? 0) }
  public var resolvedContributionCount: Int { max(0, contributionCount ?? replyCount) }
  public var capabilities: MIRAWallNoteCapabilities {
    MIRAWallNoteCapabilities(
      canSign: viewerIsAuthor != true,
      canCollaborate: allowContributions == true,
      canManageCollaboration: viewerIsAuthor == true,
      hasLocation: location != nil,
      hasBackSide: canFlip,
      hasVoice: isVoiceNote
    )
  }

  public func displayingBackSide() -> MIRAWallNote {
    guard canFlip, let backBody else { return self }
    var back = MIRAWallNote(
      id: id,
      wallId: wallId,
      publishingIdentity: publishingIdentity,
      body: backBody,
      category: category,
      colorToken: backColorToken ?? colorToken,
      styleToken: backStyleToken ?? styleToken,
      mediaUrl: nil,
      mediaThumbnailUrl: nil,
      worldX: worldX,
      worldY: worldY,
      width: width,
      height: height,
      rotation: rotation,
      zIndex: zIndex,
      approximateLocation: approximateLocation,
      createdAt: createdAt,
      updatedAt: updatedAt,
      saveCount: saveCount,
      reactionCount: reactionCount,
      replyCount: replyCount,
      reactedByViewer: reactedByViewer,
      savedByViewer: savedByViewer,
      authorPreview: authorPreview
    )
    back.noteType = "text"
    back.hasBackSide = false
    back.allowContributions = allowContributions
    back.signatureCount = signatureCount
    back.contributionCount = contributionCount
    back.signedByViewer = signedByViewer
    back.viewerIsAuthor = viewerIsAuthor
    back.location = location
    back.document = nil
    back.canvas = nil
    return back
  }

  public func updating(
    reacted: Bool? = nil,
    reactionCount: Int? = nil,
    saved: Bool? = nil,
    saveCount: Int? = nil,
    replyCount: Int? = nil,
    signed: Bool? = nil,
    signatureCount: Int? = nil,
    contributionCount: Int? = nil,
    allowContributions: Bool? = nil
  ) -> MIRAWallNote {
    var updated = MIRAWallNote(
      id: id,
      wallId: wallId,
      publishingIdentity: publishingIdentity,
      body: body,
      category: category,
      colorToken: colorToken,
      styleToken: styleToken,
      mediaUrl: mediaUrl,
      mediaThumbnailUrl: mediaThumbnailUrl,
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
    updated.noteType = noteType
    updated.backBody = backBody
    updated.backColorToken = backColorToken
    updated.backStyleToken = backStyleToken
    updated.hasBackSide = hasBackSide
    updated.allowContributions = allowContributions ?? self.allowContributions
    updated.signatureCount = signatureCount ?? self.signatureCount
    updated.contributionCount = contributionCount ?? self.contributionCount
    updated.signedByViewer = signed ?? signedByViewer
    updated.viewerIsAuthor = viewerIsAuthor
    updated.voice = voice
    updated.location = location
    updated.document = document
    updated.canvas = canvas
    return updated
  }
}

public struct MIRAWallNoteCapabilities: Hashable {
  public let canSign: Bool
  public let canCollaborate: Bool
  public let canManageCollaboration: Bool
  public let hasLocation: Bool
  public let hasBackSide: Bool
  public let hasVoice: Bool
}

public struct MIRAWallVoiceMetadata: Codable, Hashable {
  public let mediaId: String
  public let url: String?
  public let durationSeconds: Double
  public let waveform: [Double]
}

public struct MIRAWallLocationPreview: Codable, Hashable {
  public let label: String
  public let city: String?
  public let country: String?
  public let distanceKm: Double?

  public var distanceLabel: String? {
    guard let distanceKm else { return nil }
    let miles = distanceKm * 0.621371
    if miles < 0.1 { return "Nearby" }
    return String(format: "%.1f mi away", miles)
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

public typealias MIRAWallContribution = MIRAWallReply

public struct MIRAWallContributionsResponse: Decodable {
  public let contributions: [MIRAWallContribution]
  public let nextAfter: String?
}

public struct MIRAWallContributionResponse: Decodable {
  public let contribution: MIRAWallContribution
  public let contributionCount: Int?
}

public struct MIRAWallSignatureToggleResponse: Decodable {
  public let signed: Bool
  public let signatureCount: Int
}

public struct MIRAWallSignaturePoint: Codable, Hashable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct MIRAWallSignatureStroke: Codable, Hashable {
  public let points: [MIRAWallSignaturePoint]

  public init(points: [MIRAWallSignaturePoint]) {
    self.points = points
  }
}

public struct MIRAWallSignatureDrawing: Codable, Hashable {
  public let version: Int
  public let strokes: [MIRAWallSignatureStroke]

  public init(version: Int = 1, strokes: [MIRAWallSignatureStroke]) {
    self.version = version
    self.strokes = strokes
  }

  public var pointCount: Int {
    strokes.reduce(0) { $0 + $1.points.count }
  }

  public var isEmpty: Bool {
    pointCount < 2
  }
}

public struct MIRAWallSignatureBody: Encodable {
  public let signed: Bool
  public let drawing: MIRAWallSignatureDrawing?

  public init(signed: Bool, drawing: MIRAWallSignatureDrawing? = nil) {
    self.signed = signed
    self.drawing = drawing
  }
}

public struct MIRAWallSigner: Codable, Identifiable, Hashable {
  public let userId: String
  public let username: String?
  public let displayName: String?
  public let avatarUrl: String?
  public let signedAt: String
  public let drawing: MIRAWallSignatureDrawing?

  public var id: String { userId }
  public var title: String {
    let cleanUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cleanUsername.isEmpty { return "@\(cleanUsername)" }
    let cleanName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleanName.isEmpty ? "Captro member" : cleanName
  }
}

public struct MIRAWallSignersResponse: Decodable {
  public let signers: [MIRAWallSigner]
  public let nextBefore: String?
}

public struct MIRAWallCollaborationBody: Encodable {
  public let allowContributions: Bool
}

public struct MIRAWallCollaborationResponse: Decodable {
  public let allowContributions: Bool
}

public struct MIRACreateWallNoteBody: Encodable {
  public let wallId: String
  public let publishingIdentity: String
  public let body: String
  public let category: String?
  public let colorToken: String
  public let styleToken: String
  public let mediaAssetId: String?
  public let mediaUrl: String?
  public let worldX: Double
  public let worldY: Double
  public let width: Double
  public let height: Double
  public let rotation: Double
  public let approximateLocation: String?
  public let noteType: String?
  public let backBody: String?
  public let backColorToken: String?
  public let backStyleToken: String?
  public let allowContributions: Bool?
  public let voiceMediaId: String?
  public let voiceDurationSeconds: Double?
  public let voiceWaveform: [Double]?
  public let location: MIRACreateWallLocationBody?
  public let document: MIRANoteDocument?
  public let canvas: MIRANoteCanvas?
}

public struct MIRACreateWallLocationBody: Encodable {
  public let enabled: Bool
  public let label: String?
  public let city: String?
  public let country: String?
  public let latitude: Double?
  public let longitude: Double?
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
