import Foundation

public struct MIRAUser: Decodable, Identifiable, Hashable {
  public let id: String
  public let username: String?
  public let fullName: String?
  public let profileImage: String?
  public let bio: String?
  public let followersCount: Int?
  public let followingCount: Int?
  public let postsCount: Int?

  public var displayName: String {
    username?.isEmpty == false ? username! : (fullName?.isEmpty == false ? fullName! : "mira")
  }
}

public struct MIRAPost: Decodable, Identifiable, Hashable {
  public let id: String
  public let userId: String?
  public let userUsername: String?
  public let userFullName: String?
  public let userProfileImage: String?
  public let content: String?
  public let caption: String?
  public let image: String?
  public let images: FlexibleStringArray?
  public let mediaTypes: FlexibleStringArray?
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
    let raw = (caption?.isEmpty == false ? caption : content) ?? ""
    let first = raw.components(separatedBy: .newlines).first ?? raw
    return first.isEmpty ? "MIRA post" : first
  }

  public var bodyText: String {
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
      content: content,
      caption: caption,
      image: image,
      images: images,
      mediaTypes: mediaTypes,
      createdAt: createdAt,
      likesCount: likesCount ?? self.likesCount,
      commentsCount: commentsCount,
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

public struct MIRANote: Decodable, Identifiable, Hashable {
  public let id: String
  public let body: String?
  public let mediaUrl: String?
  public let createdAt: String?
  public let reactionsCount: Int?
  public let commentsCount: Int?
  public let sharesCount: Int?
  public let reacted: Bool?
  public let user: MIRAUser?
}

public struct MIRAStatusPreview: Decodable, Identifiable, Hashable {
  public let id: String
}

public struct MIRAStoryGroup: Decodable, Identifiable, Hashable {
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

public struct MIRAWallet: Decodable, Hashable {
  public let balance: Int?
  public let premiumActive: Bool?
  public let premiumPlan: String?
}

public struct MIRAConversation: Decodable, Identifiable, Hashable {
  public let id: String
  public let type: String?
  public let otherUserId: String?
  public let otherUsername: String?
  public let otherFullName: String?
  public let otherProfileImage: String?
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
}

public struct MIRAMessage: Decodable, Identifiable, Hashable {
  public let id: String
  public let senderId: String?
  public let receiverId: String?
  public let content: String?
  public let mediaUrl: String?
  public let mediaType: String?
  public let createdAt: String?
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
  public let visibility: String
  public let clientRequestId: String
}

public struct CreateNoteBody: Encodable {
  public let body: String
  public let mediaUrl: String?
  public let color: String?
}

public struct SendMessageBody: Encodable {
  public let receiverId: String
  public let content: String
}

public struct TypingBody: Encodable {
  public let peerId: String
  public let isTyping: Bool
}

public struct NoteInteractionBody: Encodable {
  public let kind: String
  public let value: String?
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
}

public struct PostSaveResponse: Decodable {
  public let saved: Bool?
  public let savesCount: Int?
}

public struct NoteCommentBody: Encodable {
  public let body: String
  public let parentId: String?
}

public struct PostCommentBody: Encodable {
  public let content: String
}

public struct FlexibleStringArray: Decodable, Hashable {
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
}

public struct FlexibleBool: Decodable, Hashable {
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
}

public struct FlexibleJSONText: Decodable, Hashable {
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
}
