import Foundation

/// Opt-in cursor response; older servers continue returning their array shape.
/// A filtered empty page with a continuation is not the end of the feed.
struct CaptroFeedPage: Decodable {
  let posts: [MIRAPost]
  let nextCursor: String?
  let hasMore: Bool
  let usesCursor: Bool

  init(legacy posts: [MIRAPost], limit: Int) {
    self.posts = posts; nextCursor = nil; hasMore = posts.count >= limit; usesCursor = false
  }
  enum CodingKeys: String, CodingKey { case posts, nextCursor, hasMore }
  init(from decoder: Decoder) throws {
    if let array = try? decoder.singleValueContainer().decode([MIRAPost].self) {
      posts = array; nextCursor = nil; hasMore = array.count >= 12; usesCursor = false
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    posts = try container.decode([MIRAPost].self, forKey: .posts)
    nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    hasMore = try container.decode(Bool.self, forKey: .hasMore)
    usesCursor = true
    if hasMore && (nextCursor?.isEmpty != false) {
      throw DecodingError.dataCorruptedError(forKey: .nextCursor, in: container,
        debugDescription: "A continuing feed page requires a cursor.")
    }
  }
}
