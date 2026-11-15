import Foundation

enum CaptroProfessionalKind: String, CaseIterable, Identifiable, Codable {
  case creator, business
  var id: String { rawValue }
  var title: String { self == .creator ? "Creator / Gig" : "Business" }
  var categories: [String] { self == .creator
    ? ["musician", "performer", "artist", "photographer", "filmmaker", "freelancer", "other_creative"]
    : ["coffee_bakery", "street_food", "shop", "small_brand", "service", "other_business"] }
  static func label(_ value: String) -> String {
    ["musician": "Independent musician", "coffee_bakery": "Café / bakery", "street_food": "Street vendor",
     "other_creative": "Creative professional", "other_business": "Business", "small_brand": "Small brand",
     "service": "Service business"][value] ?? value.capitalized
  }
}
struct CaptroProfessionalData: Codable, Hashable {
  var displayName = ""
  var category = ""
  var description = ""
  var links: [String] = []
  var pickup = false
  var area = ""
  var portfolioPostIds: [String] = []
  func valid(for kind: CaptroProfessionalKind) -> Bool {
    !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayName.count <= 80 &&
    kind.categories.contains(category) && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    description.count <= 500 && (kind != .business || !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
    links.count <= 3 && links.allSatisfy { raw in
      guard let url = URLComponents(string: raw) else { return false }
      return url.scheme == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
  }
}
struct CaptroProfessionalRecord: Decodable, Identifiable {
  let role: CaptroProfessionalKind
  let status: String
  let publicData: CaptroProfessionalData
  let version: Int
  var reviewerMessage: String?
  var applicantMessage: String?
  var statusMessage: String?
  var id: String { role.rawValue }
  var statusLabel: String { ["draft":"Draft", "under_review":"Under review", "needs_changes":"Needs changes", "approved":"Approved", "declined":"Declined", "active":"Approved", "suspended":"Suspended", "removed":"Removed"][status] ?? "Unavailable" }
}
struct CaptroProfessionalState: Decodable {
  var applications: [CaptroProfessionalRecord]
  var roles: [CaptroProfessionalRecord]
  var studioUrl: String?
}
public struct CaptroProfessionalPublicRole: Codable, Hashable, Identifiable {
  public let role: String
  public let displayName: String
  public let category: String
  public let description: String
  public let links: [String]
  public let area: String
  public let pickup: Bool
  public var shops: [Shop]?
  public var portfolio: [MIRAPost]?
  public var id: String { role }
  public struct Shop: Codable, Hashable, Identifiable { public let id: String; public let name: String }
}

func captroProfessionalMoments(_ posts: [MIRAPost], user: MIRAUser?) -> [MIRAPost] {
  let portfolio = user?.professional?.first { $0.role == "creator" }?.portfolio ?? []
  var seen = Set<String>()
  return (portfolio + posts).filter { post in
    seen.insert(post.id).inserted && !post.isLegacyOrdinaryTextPost && !post.isProfilePlan && post.captroEditorialCardContent.type != .club
  }
}
