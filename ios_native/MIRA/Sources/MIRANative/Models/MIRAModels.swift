import Foundation
import CoreGraphics

public struct MIRAUser: Codable, Identifiable, Hashable {
  public let id: String
  public let username: String?
  public let fullName: String?
  public let profileImage: String?
  public let bio: String?
  public let email: String?
  public let phone: String?
  public let phoneVerified: Bool?
  public let followersCount: Int?
  public let followingCount: Int?
  public let postsCount: Int?
  public let isFollowing: Bool?
  public let isPrivate: Bool?
  public let isPremium: Bool?
  public let language: String?

  public var displayName: String {
    username?.isEmpty == false ? username! : (fullName?.isEmpty == false ? fullName! : "mira")
  }

  public var viewerFollowing: Bool {
    isFollowing == true
  }
}

public struct MIRAPost: Codable, Identifiable, Hashable {
  public let id: String
  public let userId: String?
  public let userUsername: String?
  public let userFullName: String?
  public let userProfileImage: String?
  public let title: String?
  public let content: String?
  public let caption: String?
  public let image: String?
  public let images: FlexibleStringArray?
  public let mediaTypes: FlexibleStringArray?
  public let mediaDimensions: FlexibleMediaDimensions?
  public let location: String?
  public let postType: String?
  public let placeId: String?
  public let placeName: String?
  public let placeLat: Double?
  public let placeLng: Double?
  public let taggedUsers: [MIRATaggedUserPayload]?
  public let createdAt: String?
  public let likesCount: Int?
  public let commentsCount: Int?
  public let savesCount: Int?
  public let sharesCount: Int?
  public let viewsCount: Int?
  public let isLiked: Bool?
  public let isSaved: Bool?
  public let isFollowing: Bool?
  public let saved: FlexibleBool?
  public let following: FlexibleBool?
  public let followed: FlexibleBool?

  public var titleText: String {
    if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let raw = (caption?.isEmpty == false ? caption : content) ?? ""
    let first = raw.components(separatedBy: .newlines).first ?? raw
    return first.isEmpty ? "MIRA post" : first
  }

  public var bodyText: String {
    if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return ((caption?.isEmpty == false ? caption : content) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let raw = (caption?.isEmpty == false ? caption : content) ?? ""
    let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : ""
  }

  public var mediaURLs: [String] {
    var urls: [String] = []
    if let image, !image.isEmpty { urls.append(image) }
    urls.append(contentsOf: images?.values ?? [])
    var seen = Set<String>()
    return urls.filter { seen.insert($0).inserted }
  }

  public var mediaHeightToWidthRatios: [CGFloat] {
    mediaDimensions?.values.compactMap(\.heightToWidthRatio) ?? []
  }

  public var placeDisplayName: String? {
    let name = placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty { return name }
    let fallback = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return fallback.isEmpty ? nil : fallback
  }

  public var placeDisplaySubtitle: String? {
    guard
      let location,
      !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != (placeDisplayName ?? "").lowercased()
    else {
      return nil
    }
    return location.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var viewerSaved: Bool {
    if let isSaved { return isSaved }
    return saved?.value == true
  }

  public var viewerFollowing: Bool {
    if let isFollowing { return isFollowing }
    return following?.value == true || followed?.value == true
  }

  public func updating(
    liked: Bool? = nil,
    likesCount: Int? = nil,
    commentsCount: Int? = nil,
    saved: Bool? = nil,
    savesCount: Int? = nil,
    following: Bool? = nil
  ) -> MIRAPost {
    MIRAPost(
      id: id,
      userId: userId,
      userUsername: userUsername,
      userFullName: userFullName,
      userProfileImage: userProfileImage,
      title: title,
      content: content,
      caption: caption,
      image: image,
      images: images,
      mediaTypes: mediaTypes,
      mediaDimensions: mediaDimensions,
      location: location,
      postType: postType,
      placeId: placeId,
      placeName: placeName,
      placeLat: placeLat,
      placeLng: placeLng,
      taggedUsers: taggedUsers,
      createdAt: createdAt,
      likesCount: likesCount ?? self.likesCount,
      commentsCount: commentsCount ?? self.commentsCount,
      savesCount: savesCount ?? self.savesCount,
      sharesCount: sharesCount,
      viewsCount: viewsCount,
      isLiked: liked ?? isLiked,
      isSaved: saved ?? isSaved,
      isFollowing: following ?? isFollowing,
      saved: self.saved,
      following: self.following,
      followed: self.followed
    )
  }
}

public struct MIRATaggedUserPayload: Codable, Hashable, Identifiable {
  public let id: String
  public let username: String?
  public let fullName: String?
  public let profileImage: String?

  public init(id: String, username: String?, fullName: String?, profileImage: String?) {
    self.id = id
    self.username = username
    self.fullName = fullName
    self.profileImage = profileImage
  }
}

public struct MIRAMediaDimension: Codable, Hashable {
  public let width: Double?
  public let height: Double?
  public let ratio: Double?
  public let format: String?
  public let type: String?

  enum CodingKeys: String, CodingKey {
    case width
    case height
    case ratio
    case aspectRatio
    case aspectRatioSnake = "aspect_ratio"
    case format
    case type
  }

  public init(width: Double?, height: Double?, ratio: Double?, format: String?, type: String?) {
    self.width = width
    self.height = height
    self.ratio = ratio
    self.format = format
    self.type = type
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    width = Self.decodeDouble(container, keys: [.width])
    height = Self.decodeDouble(container, keys: [.height])
    ratio = Self.decodeDouble(container, keys: [.ratio, .aspectRatio, .aspectRatioSnake])
    let explicitFormat = try? container.decodeIfPresent(String.self, forKey: .format)
    let ratioText = Self.decodeString(container, keys: [.ratio, .aspectRatio, .aspectRatioSnake])
    format = explicitFormat ?? ratioText
    type = try? container.decodeIfPresent(String.self, forKey: .type)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(width, forKey: .width)
    try container.encodeIfPresent(height, forKey: .height)
    try container.encodeIfPresent(ratio, forKey: .ratio)
    try container.encodeIfPresent(format, forKey: .format)
    try container.encodeIfPresent(type, forKey: .type)
  }

  public var heightToWidthRatio: CGFloat? {
    let widthValue = width ?? 0
    let heightValue = height ?? 0
    if widthValue > 0, heightValue > 0 {
      return CGFloat(heightValue / widthValue)
    }
    if let ratio, ratio > 0 {
      // Backend/frontend stores ratio as width / height. Feed sizing needs height / width.
      return CGFloat(1 / ratio)
    }
    return MIRAMediaSizing.heightToWidthRatio(forFormat: format)
  }

  private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Double? {
    for key in keys {
      if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
        return value
      }
      if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
        return Double(intValue)
      }
      if let string = try? container.decodeIfPresent(String.self, forKey: key),
         let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return value
      }
    }
    return nil
  }

  private static func decodeString(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
    for key in keys {
      if let string = try? container.decodeIfPresent(String.self, forKey: key) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return nil
  }
}

public struct MIRANote: Codable, Identifiable, Hashable {
  public let id: String
  public let body: String?
  public let mediaUrl: String?
  public let createdAt: String?
  public let reactionsCount: Int?
  public let commentsCount: Int?
  public let sharesCount: Int?
  public let reacted: Bool?
  public let user: MIRAUser?

  public func updating(reactionsCount: Int? = nil, commentsCount: Int? = nil, sharesCount: Int? = nil, reacted: Bool? = nil) -> MIRANote {
    MIRANote(
      id: id,
      body: body,
      mediaUrl: mediaUrl,
      createdAt: createdAt,
      reactionsCount: reactionsCount ?? self.reactionsCount,
      commentsCount: commentsCount ?? self.commentsCount,
      sharesCount: sharesCount ?? self.sharesCount,
      reacted: reacted ?? self.reacted,
      user: user
    )
  }
}

public struct MIRAGifItem: Decodable, Identifiable, Hashable {
  public let id: String
  public let title: String?
  public let previewUrl: String?
  public let mediaUrl: String?
  public let width: Int?
  public let height: Int?
}

public struct MIRAGifSearchResponse: Decodable, Hashable {
  public let gifs: [MIRAGifItem]
}

public struct MIRAStatusPreview: Codable, Identifiable, Hashable {
  public let id: String
  public let userId: String?
  public let content: String?
  public let image: String?
  public let backgroundColor: String?
  public let textColor: String?
  public let createdAt: String?
  public let expiresAt: String?

  public var mediaURL: String? {
    guard let image, !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return image
  }
}

public struct MIRAStoryGroup: Codable, Identifiable, Hashable {
  public var id: String { userId }
  public let userId: String
  public let userUsername: String?
  public let userFullName: String?
  public let userProfileImage: String?
  public let hasUnviewed: Bool?
  public let statuses: [MIRAStatusPreview]?

  public var displayName: String {
    userFullName?.isEmpty == false ? userFullName! : (userUsername?.isEmpty == false ? userUsername! : "Story")
  }
}

public struct MIRAComment: Decodable, Identifiable, Hashable {
  public let id: String
  public let content: String?
  public let body: String?
  public let parentId: String?
  public let createdAt: String?
  public let likesCount: Int?
  public let likedByMe: Bool?
  public let user: MIRAUser?

  public var text: String { body ?? content ?? "" }
}

public struct MIRAWallet: Codable, Hashable {
  public let balance: Int?
  public let premiumActive: Bool?
  public let premiumPlan: String?
}

public struct MIRAConversation: Codable, Identifiable, Hashable {
  public let id: String
  public let type: String?
  public let otherUserId: String?
  public let otherUsername: String?
  public let otherFullName: String?
  public let otherProfileImage: String?
  public let otherLastSeenAt: String?
  public let otherIsOnline: Bool?
  public let otherIsTyping: Bool?
  public let lastMessage: String?
  public let lastMessageTime: String?
  public let updatedAt: String?
  public let unreadCount: Int?
  public let groupId: String?
  public let groupName: String?
  public let memberCount: Int?

  public var displayName: String {
    groupName?.isEmpty == false ? groupName! : (otherUsername?.isEmpty == false ? otherUsername! : (otherFullName ?? "Chat"))
  }

  public var isGroup: Bool {
    type == "group" || groupId != nil
  }

  enum CodingKeys: String, CodingKey {
    case id, type
    case otherUser
    case otherUserId, otherUsername, otherFullName, otherProfileImage, otherLastSeenAt, otherIsOnline, otherIsTyping
    case lastMessage, lastMessageTime, updatedAt, unreadCount
    case groupId, groupName, memberCount
  }

  enum OtherUserKeys: String, CodingKey {
    case id, username, fullName, profileImage, lastSeenAt, isOnline, isTyping
  }

  public init(
    id: String,
    type: String?,
    otherUserId: String?,
    otherUsername: String?,
    otherFullName: String?,
    otherProfileImage: String?,
    otherLastSeenAt: String?,
    otherIsOnline: Bool?,
    otherIsTyping: Bool?,
    lastMessage: String?,
    lastMessageTime: String?,
    updatedAt: String?,
    unreadCount: Int?,
    groupId: String?,
    groupName: String?,
    memberCount: Int?
  ) {
    self.id = id
    self.type = type
    self.otherUserId = otherUserId
    self.otherUsername = otherUsername
    self.otherFullName = otherFullName
    self.otherProfileImage = otherProfileImage
    self.otherLastSeenAt = otherLastSeenAt
    self.otherIsOnline = otherIsOnline
    self.otherIsTyping = otherIsTyping
    self.lastMessage = lastMessage
    self.lastMessageTime = lastMessageTime
    self.updatedAt = updatedAt
    self.unreadCount = unreadCount
    self.groupId = groupId
    self.groupName = groupName
    self.memberCount = memberCount
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    lastMessage = try? container.decodeIfPresent(String.self, forKey: .lastMessage)
    lastMessageTime = try? container.decodeIfPresent(String.self, forKey: .lastMessageTime)
    updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    unreadCount = try? container.decodeIfPresent(Int.self, forKey: .unreadCount)
    groupId = try? container.decodeIfPresent(String.self, forKey: .groupId)
    groupName = try? container.decodeIfPresent(String.self, forKey: .groupName)
    memberCount = try? container.decodeIfPresent(Int.self, forKey: .memberCount)

    let nested = try? container.nestedContainer(keyedBy: OtherUserKeys.self, forKey: .otherUser)
    func nestedString(_ key: OtherUserKeys) -> String? {
      guard let nested else { return nil }
      return try? nested.decodeIfPresent(String.self, forKey: key)
    }
    func nestedBool(_ key: OtherUserKeys) -> Bool? {
      guard let nested else { return nil }
      return try? nested.decodeIfPresent(Bool.self, forKey: key)
    }
    otherUserId = (try? container.decodeIfPresent(String.self, forKey: .otherUserId)) ?? nestedString(.id)
    otherUsername = (try? container.decodeIfPresent(String.self, forKey: .otherUsername)) ?? nestedString(.username)
    otherFullName = (try? container.decodeIfPresent(String.self, forKey: .otherFullName)) ?? nestedString(.fullName)
    otherProfileImage = (try? container.decodeIfPresent(String.self, forKey: .otherProfileImage)) ?? nestedString(.profileImage)
    otherLastSeenAt = (try? container.decodeIfPresent(String.self, forKey: .otherLastSeenAt)) ?? nestedString(.lastSeenAt)
    otherIsOnline = (try? container.decodeIfPresent(Bool.self, forKey: .otherIsOnline)) ?? nestedBool(.isOnline)
    otherIsTyping = (try? container.decodeIfPresent(Bool.self, forKey: .otherIsTyping)) ?? nestedBool(.isTyping)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(type, forKey: .type)
    try container.encodeIfPresent(otherUserId, forKey: .otherUserId)
    try container.encodeIfPresent(otherUsername, forKey: .otherUsername)
    try container.encodeIfPresent(otherFullName, forKey: .otherFullName)
    try container.encodeIfPresent(otherProfileImage, forKey: .otherProfileImage)
    try container.encodeIfPresent(otherLastSeenAt, forKey: .otherLastSeenAt)
    try container.encodeIfPresent(otherIsOnline, forKey: .otherIsOnline)
    try container.encodeIfPresent(otherIsTyping, forKey: .otherIsTyping)
    try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
    try container.encodeIfPresent(lastMessageTime, forKey: .lastMessageTime)
    try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    try container.encodeIfPresent(unreadCount, forKey: .unreadCount)
    try container.encodeIfPresent(groupId, forKey: .groupId)
    try container.encodeIfPresent(groupName, forKey: .groupName)
    try container.encodeIfPresent(memberCount, forKey: .memberCount)
  }
}

public struct MIRAMessage: Decodable, Identifiable, Hashable {
  public let id: String
  public let groupId: String?
  public let senderId: String?
  public let receiverId: String?
  public let content: String?
  public let mediaUrl: String?
  public let mediaType: String?
  public let createdAt: String?
  public let username: String?
  public let fullName: String?
  public let profileImage: String?
}

public struct MIRAPresence: Decodable, Hashable {
  public let userId: String?
  public let lastSeenAt: String?
  public let isOnline: Bool?
  public let isTyping: Bool?
}

public struct MIRANotification: Decodable, Identifiable, Hashable {
  public let id: String
  public let type: String?
  public let title: String?
  public let body: String?
  public let data: FlexibleJSONText?
  public let isRead: FlexibleBool?
  public let createdAt: String?
}

public struct MIRAAuthResponse: Decodable, Hashable {
  public let accessToken: String
  public let tokenType: String?
  public let user: MIRAUser
}

public struct MIRAAuthLoginBody: Encodable {
  public let email: String
  public let password: String
}

public struct MIRAAuthRegisterBody: Encodable {
  public let email: String
  public let password: String
  public let username: String
  public let fullName: String
}

public struct MIRAAppleOAuthBody: Encodable {
  public let idToken: String
  public let email: String?
  public let fullName: String?
  public let appleUser: String?
}

public struct MIRAUploadImageBody: Encodable {
  public let image: String
  public let filename: String
}

public struct MIRAMediaUploadResponse: Decodable, Hashable {
  public let url: String?
  public let id: String?
  public let videoUid: String?
  public let uploadUrl: String?
  public let source: String?
}

public struct MIRAStreamPlaybackInfo: Decodable, Hashable {
  public let uid: String?
  public let hls: String?
  public let dash: String?
  public let thumbnail: String?
  public let ready: Bool?
}

public struct MIRALibraryCollection: Decodable, Identifiable, Hashable {
  public var id: String { collection ?? name ?? "collection" }
  public let collection: String?
  public let name: String?
  public let count: Int?
}

public struct MIRAWalletTransaction: Decodable, Identifiable, Hashable {
  public let id: String
  public let amount: Int?
  public let direction: String?
  public let reason: String?
  public let createdAt: String?
}

public struct CreatePostBody: Encodable {
  public let title: String
  public let content: String
  public let image: String?
  public let images: [String]
  public let mediaTypes: [String]
  public let mediaDimensions: [MIRAMediaDimension]
  public let editorOverlays: [MIRAEditorUploadMetadata]?
  public let location: String?
  public let postType: String?
  public let placeId: String?
  public let placeName: String?
  public let placeLat: Double?
  public let placeLng: Double?
  public let taggedUsers: [MIRATaggedUserPayload]?
  public let visibility: String
  public let clientRequestId: String

  public init(
    title: String,
    content: String,
    image: String?,
    images: [String],
    mediaTypes: [String],
    mediaDimensions: [MIRAMediaDimension],
    editorOverlays: [MIRAEditorUploadMetadata]? = nil,
    location: String? = nil,
    postType: String? = nil,
    placeId: String? = nil,
    placeName: String? = nil,
    placeLat: Double? = nil,
    placeLng: Double? = nil,
    taggedUsers: [MIRATaggedUserPayload]? = nil,
    visibility: String,
    clientRequestId: String
  ) {
    self.title = title
    self.content = content
    self.image = image
    self.images = images
    self.mediaTypes = mediaTypes
    self.mediaDimensions = mediaDimensions
    self.editorOverlays = editorOverlays
    self.location = location
    self.postType = postType
    self.placeId = placeId
    self.placeName = placeName
    self.placeLat = placeLat
    self.placeLng = placeLng
    self.taggedUsers = taggedUsers
    self.visibility = visibility
    self.clientRequestId = clientRequestId
  }
}

public struct MIRAEditorUploadMetadata: Encodable, Hashable {
  public let type: String
  public let mediaIndex: Int
  public let wasEdited: Bool
  public let editorVersion: String
  public let appliedFilter: String
  public let hasTextOverlay: Bool

  public init(mediaIndex: Int, metadata: MIRANativeEditedMediaMetadata) {
    self.type = "native_editor"
    self.mediaIndex = mediaIndex
    self.wasEdited = metadata.wasEdited
    self.editorVersion = metadata.editorVersion
    self.appliedFilter = metadata.appliedFilter
    self.hasTextOverlay = metadata.hasTextOverlay
  }
}

public struct CreateNoteBody: Encodable {
  public let body: String
  public let mediaUrl: String?
  public let color: String?
}

public struct CreateStatusBody: Encodable {
  public let content: String
  public let image: String?
  public let backgroundColor: String
  public let textColor: String
  public let visibility: String
  public let editorMetadata: MIRANativeEditedMediaMetadata?

  public init(
    content: String,
    image: String?,
    backgroundColor: String,
    textColor: String,
    visibility: String,
    editorMetadata: MIRANativeEditedMediaMetadata? = nil
  ) {
    self.content = content
    self.image = image
    self.backgroundColor = backgroundColor
    self.textColor = textColor
    self.visibility = visibility
    self.editorMetadata = editorMetadata
  }
}

public struct SendMessageBody: Encodable {
  public let receiverId: String
  public let content: String
  public let mediaUrl: String?
  public let mediaType: String?

  public init(receiverId: String, content: String, mediaUrl: String? = nil, mediaType: String? = nil) {
    self.receiverId = receiverId
    self.content = content
    self.mediaUrl = mediaUrl
    self.mediaType = mediaType
  }
}

public struct GroupMessageBody: Encodable {
  public let content: String
  public let mediaUrl: String?
  public let mediaType: String?

  public init(content: String, mediaUrl: String? = nil, mediaType: String? = nil) {
    self.content = content
    self.mediaUrl = mediaUrl
    self.mediaType = mediaType
  }
}

public struct CreateGroupChatBody: Encodable {
  public let name: String
  public let memberIds: [String]
}

public struct MIRAGroupChatCreatedResponse: Decodable, Hashable {
  public let id: String
  public let name: String?
  public let memberCount: Int?
  public let createdBy: String?
  public let createdAt: String?
}

public struct MIRAGroupInfo: Decodable, Hashable {
  public let id: String
  public let name: String?
  public let createdBy: String?
  public let memberCount: Int?
}

public struct MIRAGroupMessagesResponse: Decodable, Hashable {
  public let group: MIRAGroupInfo?
  public let messages: [MIRAMessage]
}

public struct TypingBody: Encodable {
  public let peerId: String
  public let isTyping: Bool
}

public struct NoteInteractionBody: Encodable {
  public let kind: String
  public let value: String?
}

public struct NoteInteractionResponse: Decodable {
  public let active: Bool?
  public let kind: String?
}

public struct NoteReportBody: Encodable {
  public let reason: String
  public let details: String?
}

public struct FollowBody: Encodable {
  public let following: Bool
}

public struct LikeBody: Encodable {
  public let liked: Bool
}

public struct SaveCollectionBody: Encodable {
  public let collection: String
}

public struct FollowResponse: Decodable {
  public let following: Bool?
  public let followingCount: Int?
  public let followersCount: Int?
}

public struct PostLikeResponse: Decodable {
  public let liked: Bool?
  public let likesCount: Int?
  public let saved: Bool?
  public let savesCount: Int?
  public let commentsCount: Int?
}

public struct PostSaveResponse: Decodable {
  public let saved: Bool?
  public let savesCount: Int?
  public let liked: Bool?
  public let likesCount: Int?
  public let commentsCount: Int?
}

public struct NoteCommentBody: Encodable {
  public let body: String
  public let parentId: String?
}

public struct PostCommentBody: Encodable {
  public let content: String
}

public struct FlexibleStringArray: Codable, Hashable {
  public let values: [String]

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let array = try? container.decode([String].self) {
      values = array
      return
    }
    if let string = try? container.decode(String.self) {
      if string.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["),
         let data = string.data(using: .utf8),
         let decoded = try? JSONDecoder().decode([String].self, from: data) {
        values = decoded
      } else if string.isEmpty {
        values = []
      } else {
        values = [string]
      }
      return
    }
    values = []
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(values)
  }
}

public struct FlexibleMediaDimensions: Codable, Hashable {
  public let values: [MIRAMediaDimension]

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let array = try? container.decode([MIRAMediaDimension].self) {
      values = array
      return
    }
    if let dimension = try? container.decode(MIRAMediaDimension.self) {
      values = [dimension]
      return
    }
    if let dictionary = try? container.decode([String: MIRAMediaDimension].self) {
      values = dictionary.keys.sorted().compactMap { dictionary[$0] }
      return
    }
    if let string = try? container.decode(String.self) {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        values = []
        return
      }
      if let data = trimmed.data(using: .utf8) {
        if let decoded = try? JSONDecoder().decode([MIRAMediaDimension].self, from: data) {
          values = decoded
          return
        }
        if let decoded = try? JSONDecoder().decode(MIRAMediaDimension.self, from: data) {
          values = [decoded]
          return
        }
        if let decoded = try? JSONDecoder().decode([String: MIRAMediaDimension].self, from: data) {
          values = decoded.keys.sorted().compactMap { decoded[$0] }
          return
        }
      }
      values = [MIRAMediaDimension(width: nil, height: nil, ratio: nil, format: trimmed, type: nil)]
      return
    }
    values = []
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(values)
  }
}

public struct FlexibleBool: Codable, Hashable {
  public let value: Bool

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int != 0
    } else if let string = try? container.decode(String.self) {
      value = ["true", "1", "yes"].contains(string.lowercased())
    } else {
      value = false
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

public struct FlexibleJSONText: Codable, Hashable {
  public let raw: String

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      raw = string
      return
    }
    if let object = try? container.decode([String: String].self),
       let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
      raw = string
      return
    }
    raw = "{}"
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(raw)
  }
}
