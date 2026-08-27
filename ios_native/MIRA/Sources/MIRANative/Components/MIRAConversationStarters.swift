import SwiftUI

/// Deterministic, category-aware comment prompts. This is intentionally local so feed rendering
/// never waits for a network or AI request. A future provider can return the same model.
struct MIRAConversationStarter: Identifiable, Hashable {
  let id: String
  let text: String
  let category: String
  let source: String
}

enum MIRAConversationStarterEngine {
  static func starters(for post: MIRAPost, viewerID: String?) -> [MIRAConversationStarter] {
    guard shouldShow(for: post, viewerID: viewerID) else { return [] }

    let category = resolvedCategory(for: post)
    let templates = templatesByCategory[category] ?? generalTemplates
    return templates.prefix(3).map { template in
      MIRAConversationStarter(
        id: "\(category).\(template.id)",
        text: template.text,
        category: category,
        source: "template"
      )
    }
  }

  private static func shouldShow(for post: MIRAPost, viewerID: String?) -> Bool {
    guard !post.feedMediaURLs.isEmpty else { return false }
    guard post.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "private" else { return false }
    guard let viewerID, !viewerID.isEmpty else { return true }
    return post.userId != viewerID
  }

  private static func resolvedCategory(for post: MIRAPost) -> String {
    let placeSignal = [post.placeType, post.placeCategory, post.placeName]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")
    if placeSignal.contains("restaurant") || placeSignal.contains("bakery") { return "restaurant" }
    if placeSignal.contains("cafe") || placeSignal.contains("coffee") { return "coffee" }
    if placeSignal.contains("museum") || placeSignal.contains("gallery") { return "museum" }
    if placeSignal.contains("park") || placeSignal.contains("beach") || placeSignal.contains("trail") { return "nature" }
    if placeSignal.contains("stadium") || placeSignal.contains("arena") { return "sports" }

    let primary = (post.primaryCategory ?? post.category ?? "").lowercased()
    switch primary {
    case "outfits", "outfit", "fashion": return "outfit"
    case "outdoors", "outdoor", "nature": return "nature"
    case "food", "restaurant": return "restaurant"
    case "travel": return "travel"
    case "nightlife": return "nightlife"
    case "art", "photography": return primary
    case "fitness", "sports": return "sports"
    case "pets", "pet": return "pets"
    default: return "general"
    }
  }

  private static let generalTemplates = [
    Template(id: "love_this", text: "Love this!"),
    Template(id: "tell_me_more", text: "Tell me more."),
    Template(id: "recommend", text: "Would you recommend it?")
  ]

  private static let templatesByCategory: [String: [Template]] = [
    "travel": [
      Template(id: "where", text: "Where is this?"),
      Template(id: "again", text: "Would you go again?"),
      Template(id: "tips", text: "Any travel tips?")
    ],
    "restaurant": [
      Template(id: "order", text: "What did you order?"),
      Template(id: "price", text: "Worth the price?"),
      Template(id: "dish", text: "Favorite dish?")
    ],
    "coffee": [
      Template(id: "drink", text: "Best drink?"),
      Template(id: "work", text: "Good place to work?"),
      Template(id: "visit", text: "Worth visiting?")
    ],
    "museum": [
      Template(id: "exhibit", text: "Favorite exhibit?"),
      Template(id: "crowded", text: "Was it crowded?"),
      Template(id: "photos", text: "Photography allowed?")
    ],
    "nature": [
      Template(id: "where", text: "Where is this?"),
      Template(id: "hike", text: "Easy hike?"),
      Template(id: "season", text: "Best season?"),
    ],
    "outfit": [
      Template(id: "where_from", text: "Where did you get this?"),
      Template(id: "colors", text: "Love the colors."),
      Template(id: "shoes", text: "What shoes are those?")
    ],
    "sports": [
      Template(id: "game", text: "How was the game?"),
      Template(id: "moment", text: "Favorite moment?"),
      Template(id: "winner", text: "Who won?")
    ],
    "nightlife": [
      Template(id: "check_out", text: "Worth checking out?"),
      Template(id: "music", text: "What music was playing?"),
      Template(id: "back", text: "Would you go back?")
    ],
    "art": [
      Template(id: "made", text: "Did you make this?"),
      Template(id: "time", text: "How long did it take?"),
      Template(id: "detail", text: "Favorite detail?")
    ],
    "photography": [
      Template(id: "moment", text: "How did you capture this?"),
      Template(id: "location", text: "Where was this taken?"),
      Template(id: "detail", text: "Favorite detail?"),
    ],
    "pets": [
      Template(id: "name", text: "What's their name?"),
      Template(id: "cute", text: "So cute!"),
      Template(id: "age", text: "How old are they?")
    ]
  ]

  private struct Template: Hashable {
    let id: String
    let text: String
  }
}

struct MIRAConversationStartersRow: View {
  let starters: [MIRAConversationStarter]
  let onSelect: (MIRAConversationStarter) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isVisible = false

  var body: some View {
    if !starters.isEmpty {
      VStack(alignment: .leading, spacing: 7) {
        Label("Start a conversation", systemImage: "bubble.left.and.bubble.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(starters) { starter in
              Button {
                onSelect(starter)
              } label: {
                Text(starter.text)
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(MIRATheme.Color.textSecondary)
                  .lineLimit(1)
                  .padding(.horizontal, 12)
                  .frame(minHeight: 32)
                  .background(MIRATheme.Color.surfaceSoft)
                  .clipShape(Capsule())
                  .overlay {
                    Capsule().stroke(MIRATheme.Color.hairline.opacity(0.7), lineWidth: 0.75)
                  }
              }
              .buttonStyle(.miraPress)
              .accessibilityLabel("Conversation starter: \(starter.text)")
              .accessibilityHint("Opens the comment composer with this text. You can edit it before sending.")
            }
          }
          .padding(.vertical, 1)
        }
      }
      .opacity(isVisible ? 1 : 0)
      .onAppear {
        guard !isVisible else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .easeOut(duration: 0.2)) {
          isVisible = true
        }
      }
    }
  }
}
