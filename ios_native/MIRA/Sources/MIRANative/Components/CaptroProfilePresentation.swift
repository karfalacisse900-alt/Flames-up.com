import SwiftUI

/// Profile-only presentation. Does not alter feed media geometry or app theme.
enum CaptroProfileSection: String, CaseIterable, Identifiable {
  case moments = "Moments", plans = "Plans", clubs = "Clubs"
  var id: String { rawValue }
}

struct CaptroProfileShowcase: Decodable {
  var pinned: MIRAPost? = nil
  var clubs: [MIRAPost] = []
}

struct CaptroProfileLink: Identifiable, Equatable {
  let id: String
  static func url(userID: String) -> URL? {
    guard valid(userID) else { return nil }
    return URL(string: "captro://profile/\(userID)")
  }
  static func parse(_ url: URL) -> CaptroProfileLink? {
    guard url.scheme == "captro", url.host == "profile", url.query == nil, url.fragment == nil else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count == 1, valid(parts[0]) else { return nil }
    return CaptroProfileLink(id: parts[0])
  }
  private static func valid(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 120 && id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0) }
  }
}

extension Notification.Name {
  static let captroProfileSignInRequested = Notification.Name("captroProfileSignInRequested")
}

struct CaptroFollowRequestsView: View {
  let api: MIRAAPIClient
  @State private var requests: [MIRAUser] = []
  @State private var loading = true
  @State private var error: String?
  @State private var updating: String?
  var body: some View {
    List {
      if loading { ProgressView("Loading requests…") }
      if let error { Text(error); Button("Try again") { Task { await load() } } }
      if !loading && error == nil && requests.isEmpty { Text("No pending requests") }
      ForEach(requests) { user in
        VStack(alignment: .leading, spacing: 8) {
          NavigationLink(user.fullName ?? user.displayName) { UserProfileNativeView(userId: user.id, api: api) }
          HStack {
            Button("Approve") { Task { await decide(user.id, approved: true) } }
            Button("Decline") { Task { await decide(user.id, approved: false) } }
          }.buttonStyle(.bordered).disabled(updating != nil)
        }.padding(.vertical, 6)
      }
    }.navigationTitle("Follow requests").task { await load() }.refreshable { await load() }
  }
  private func load() async {
    loading = true; defer { loading = false }
    do { requests = try await api.get("/users/me/follow-requests"); error = nil }
    catch { self.error = "Could not load requests." }
  }
  private func decide(_ id: String, approved: Bool) async {
    guard updating == nil else { return }; updating = id; defer { updating = nil }
    do {
      let _: FollowResponse = try await api.post("/users/me/follow-requests/\(id)", body: Decision(approved: approved))
      await load()
    } catch { self.error = "Could not confirm this decision. Try again." }
  }
  private struct Decision: Encodable { let approved: Bool }
}

extension MIRAPost {
  var isProfilePlan: Bool {
    let type = captroEditorialCardContent.type
    return type == .event || type == .meetup
  }
}

struct CaptroProfileItemRow: View {
  let post: MIRAPost
  var pinned = false
  var body: some View {
    let card = post.captroMediaFeedCardContent
    HStack(spacing: 14) {
      let delivery = post.imageDelivery(at: 0, dataSaver: true)
      RemoteMediaView(url: delivery?.display ?? post.thumbnailMediaURLs.first ?? "", isVideo: false,
        fallbackURL: delivery?.source, additionalFallbackURLs: [delivery?.fallback].compactMap { $0 },
        contentMode: .fill, maxPixelSize: 240)
        .frame(width: 70, height: 70).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
      VStack(alignment: .leading, spacing: 4) {
        if pinned { Text("PINNED").font(.caption).foregroundStyle(.secondary) }
        Text(card.title.isEmpty ? "View moment" : card.title).font(.subheadline.weight(.semibold))
        if !card.homeStampMetadata.isEmpty { Text(card.homeStampMetadata).font(.caption).foregroundStyle(.secondary) }
        if let status = card.availabilityText, !status.isEmpty { Text(status).font(.caption.weight(.semibold)) }
        if let zone = post.detail?.commerce?.timeZone ?? post.detail?.event?.timeZone {
          Text(zone).font(.caption2).foregroundStyle(.secondary)
        }
      }.fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
  }
}

struct CaptroProfilePlans: View {
  let posts: [MIRAPost]
  let api: MIRAAPIClient
  var onPin: ((MIRAPost) -> Void)? = nil
  private func group(_ post: MIRAPost, now: Date) -> String {
    guard let date = CaptroStoryExpiry.date(post.detail?.commerce?.endsAt ?? post.detail?.event?.endsAt ?? post.detail?.commerce?.startsAt ?? post.detail?.event?.startsAt) else { return "Date unavailable" }
    return date < now ? "Past" : "Upcoming"
  }
  var body: some View {
    let plans = posts.filter(\.isProfilePlan)
    let now = Date()
    VStack(alignment: .leading, spacing: 10) {
      if plans.isEmpty { Text("No hosted plans loaded").foregroundStyle(.secondary) }
      ForEach(["Upcoming", "Past", "Date unavailable"], id: \.self) { category in
        let rows = plans.filter { group($0, now: now) == category }
        if !rows.isEmpty {
          Text(category).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
          ForEach(rows) { post in
            NavigationLink(destination: DiscoverPostDetailNativeView(post: post, api: api)) {
              CaptroProfileItemRow(post: post)
            }.buttonStyle(.plain).contextMenu {
              if let onPin { Button("Pin to profile") { onPin(post) } }
            }
          }
        }
      }
    }.padding(.horizontal, 20)
  }
}

struct CaptroProfileIntroduction: View {
  let user: MIRAUser?
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 18) {
        RemoteAvatar(url: user?.profileImage, size: 84)
        VStack(alignment: .leading, spacing: 5) {
          Text(user?.fullName?.nonemptyProfileText ?? user?.displayName ?? "Profile")
            .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
          if let username = user?.username {
            Text("@\(MIRAUsernameRules.normalized(username))").foregroundStyle(.secondary)
          }
          if let city = user?.city?.nonemptyProfileText {
            Label(city, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
          }
        }.font(.subheadline)
        Spacer(minLength: 0)
      }
      if let bio = user?.bio?.nonemptyProfileText {
        Text(bio).font(.body).fixedSize(horizontal: false, vertical: true)
      }
      if user?.privacyLocked != true, user?.viewerHasBlocked != true, user?.viewerBlockedBy != true,
         let followers = user?.followersCount, let following = user?.followingCount {
        Text("\(followers) followers · \(following) following")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      if let openTo = user?.openTo?.nonemptyProfileText {
        (Text("Open to  ").foregroundColor(.secondary) + Text(openTo))
          .font(.subheadline).fixedSize(horizontal: false, vertical: true)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct CaptroProfileTabs: View {
  @Binding var selection: CaptroProfileSection
  var body: some View {
    HStack(spacing: 0) {
      ForEach(CaptroProfileSection.allCases) { section in
        Button { selection = section } label: {
          Text(section.rawValue).font(.subheadline.weight(selection == section ? .semibold : .regular))
            .foregroundStyle(selection == section ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(alignment: .bottom) {
              if selection == section { Rectangle().frame(height: 2).padding(.horizontal, 12) }
            }
        }.buttonStyle(.plain)
          .accessibilityAddTraits(selection == section ? .isSelected : [])
          .accessibilityIdentifier("profile.tab.\(section.id.lowercased())")
      }
    }.overlay(alignment: .top) { Divider() }
  }
}

struct CaptroProfileActionStyle: ButtonStyle {
  var primary = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 46)
      .foregroundStyle(primary ? Color.white : Color.primary)
      .background(primary ? Color(white: 0.10) : Color(uiColor: .secondarySystemBackground),
                  in: RoundedRectangle(cornerRadius: 7))
      .opacity(configuration.isPressed ? 0.75 : 1)
  }
}

private extension String {
  var nonemptyProfileText: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
