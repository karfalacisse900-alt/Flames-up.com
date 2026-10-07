import Foundation

enum CaptroWritingIntent: String, Codable, CaseIterable, Identifiable {
  case wantTo = "want_to"
  case lookingFor = "looking_for"
  case concern
  var id: String { rawValue }
  var title: String {
    switch self { case .wantTo: return "Want to"; case .lookingFor: return "Looking for"; case .concern: return "Concern" }
  }
  var byline: String {
    switch self { case .wantTo: return "wants to"; case .lookingFor: return "is looking for"; case .concern: return "is concerned about" }
  }
  var placeholder: String {
    switch self { case .wantTo: return "What do you want to do?"; case .lookingFor: return "What are you looking for?"; case .concern: return "What’s on your mind?" }
  }
}

enum CaptroCompositionAudience: String, Codable, CaseIterable, Identifiable {
  case everyone = "public"
  case followers, friends
  case onlyMe = "private"
  var id: String { rawValue }
  var title: String {
    switch self { case .everyone: return "Public"; case .followers: return "Followers"; case .friends: return "Friends"; case .onlyMe: return "Only me" }
  }
  var explanation: String {
    switch self {
    case .everyone: return "Visible to people allowed to view your profile."
    case .followers: return "Visible to your followers and friends."
    case .friends: return "Visible to your Captro friends."
    case .onlyMe: return "Visible only to you."
    }
  }
  var icon: String { self == .everyone ? "globe" : self == .onlyMe ? "lock" : "person.2" }
}

/// One editing source of truth. UI/presentation and upload resources live outside it.
/// Scheduling is retained while switching intents, but never submitted for Concern.
struct CaptroCompositionDraft {
  var intent: CaptroWritingIntent = .wantTo
  var audience: CaptroCompositionAudience = .everyone
  var time: Date?
  var title = "" // Structured object name; ordinary writing has no separate title field.
  var bodyText = ""
  var mediaItems: [MIRAPickedMedia] = []
  var originalMediaItems: [MIRAPickedMedia] = []
  var selectedStampKind: CaptroStampKind = .social
  var hasSelectedStamp = false
  var momentType = "Thought"
  var eventDraft = CaptroEventDraft()
  var commerceDraft = CaptroCommerceDraft()
  var postResponse: CaptroPostResponseDraft?
  var selectedPlace: MIRAExactPostPlace?
  var voiceDraft: CaptroVoiceDraft?
  var requestID = UUID().uuidString
  var structured: Bool { [.club, .event, .meetup, .deal].contains(selectedStampKind) }
  var submittedIntent: String? { structured ? nil : intent.rawValue }
  var submittedTime: String? {
    guard !structured, intent != .concern, let time else { return nil }
    return ISO8601DateFormatter().string(from: time)
  }
  var hasWriting: Bool { !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct CaptroCreationCapabilities: Decodable {
  let structuredTypes: [String]
  var mediaWritingVersion: Int? = nil
}
