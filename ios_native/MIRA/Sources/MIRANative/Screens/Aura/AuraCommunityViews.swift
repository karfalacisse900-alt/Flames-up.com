import SwiftUI

public extension View {
  func physicalAuraCard(cornerRadius: CGFloat = 14) -> some View {
    modifier(PhysicalAuraCardModifier(cornerRadius: cornerRadius))
  }
}

private struct PhysicalAuraCardModifier: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(MIRATheme.Color.surface)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(MIRATheme.Color.textPrimary.opacity(0.88), lineWidth: 1.35)
      }
      .shadow(color: .black.opacity(0.88), radius: 0, x: 0, y: 5)
      .padding(.bottom, 5)
  }
}

public struct AuraSmallPostFeedCard: View {
  let post: AuraCommunityPost

  public init(post: AuraCommunityPost) {
    self.post = post
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RemoteAvatar(url: post.userProfileImage, size: 36)

      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 8) {
          Text(post.authorHandle)
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
          Text((post.communityCategory ?? "update").uppercased())
            .font(.caption2)
            .fontWeight(.black)
            .foregroundStyle(MIRATheme.Color.auraViolet)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MIRATheme.Color.auraVioletSoft, in: Capsule())
          Spacer(minLength: 4)
          Text(AuraCommunityFormatting.relativeDate(post.createdAt))
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textMuted)
        }

        if !post.titleText.isEmpty {
          Text(post.titleText)
            .font(.headline)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(2)
        }

        HStack(alignment: .top, spacing: 10) {
          if !post.bodyText.isEmpty {
            Text(post.bodyText)
              .font(.subheadline)
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .lineLimit(4)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          if let image = post.primaryImageURL {
            AuraCommunityRemoteImage(url: image, height: 72)
              .frame(width: 76)
          }
        }

        if post.communityAllowReplies != false {
          Label("\(post.commentsCount ?? 0) replies", systemImage: "bubble.left")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(MIRATheme.Color.textSecondary)
        } else {
          Label("Replies off", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
    }
    .padding(14)
    .physicalAuraCard()
    .accessibilityElement(children: .combine)
  }
}

@MainActor
final class AuraSmallPostDetailLoaderModel: ObservableObject {
  @Published private(set) var post: MIRAPost?
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?

  private let api: MIRAAPIClient
  private let postID: String

  init(api: MIRAAPIClient, postID: String) {
    self.api = api
    self.postID = postID
  }

  func load() async {
    guard !isLoading else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      post = try await api.get("/posts/\(postID)")
    } catch {
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "This post could not be loaded."
    }
  }
}

/// Resolves the canonical post representation before opening the existing post-detail and
/// comments experience. The feed's compact community projection is never used as fake detail data.
public struct AuraSmallPostDetailLoaderView: View {
  let api: MIRAAPIClient
  @StateObject private var model: AuraSmallPostDetailLoaderModel

  public init(api: MIRAAPIClient, postID: String) {
    self.api = api
    _model = StateObject(wrappedValue: AuraSmallPostDetailLoaderModel(api: api, postID: postID))
  }

  public var body: some View {
    Group {
      if let post = model.post {
        PostDetailNativeView(post: post, api: api)
      } else if model.isLoading || model.errorMessage == nil {
        ProgressView("Loading post…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: 16) {
          MIRAEmptyState(
            title: "Post unavailable",
            message: model.errorMessage ?? "This post could not be loaded.",
            systemImage: "bubble.left.and.exclamationmark.bubble.right"
          )
          Button("Try Again") {
            Task { await model.load() }
          }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.auraViolet)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
      }
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .task {
      if model.post == nil { await model.load() }
    }
  }
}

public struct AuraMeetupFeedCard: View {
  let post: AuraCommunityPost

  public init(post: AuraCommunityPost) {
    self.post = post
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      AuraCommunityRemoteImage(url: post.primaryImageURL, height: 158)
        .overlay(alignment: .topLeading) {
          Text("MEETUP")
            .font(.caption2)
            .fontWeight(.black)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(MIRATheme.Color.surface, in: Capsule())
            .padding(10)
        }

      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(post.titleText)
            .font(.title3)
            .fontWeight(.black)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(2)
          Spacer()
          Text(post.entryLabel)
            .font(.caption)
            .fontWeight(.black)
            .foregroundStyle(post.meetupEntryType == "aur" ? MIRATheme.Color.auraViolet : MIRATheme.Color.forest)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
              post.meetupEntryType == "aur" ? MIRATheme.Color.auraVioletSoft : MIRATheme.Color.forestSoft,
              in: Capsule()
            )
        }

        Label(post.locationLine, systemImage: "mappin.and.ellipse")
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)

        HStack {
          AuraStackedProfilePlaceholders(count: max(0, min(post.meetupJoinedCount ?? 0, 4)))
          Text(attendanceLabel)
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textSecondary)
          Spacer()
          Text(AuraCommunityFormatting.meetupDate(post.meetupStartsAt))
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
      .padding(14)
    }
    .physicalAuraCard()
    .accessibilityElement(children: .combine)
  }

  private var attendanceLabel: String {
    guard post.meetupStateAvailable != false, let count = post.meetupJoinedCount else { return "Attendance unavailable" }
    return "\(count) going"
  }
}

struct AuraStackedProfilePlaceholders: View {
  let count: Int

  var body: some View {
    HStack(spacing: -8) {
      ForEach(0..<count, id: \.self) { index in
        Circle()
          .fill(index.isMultiple(of: 2) ? MIRATheme.Color.auraVioletSoft : MIRATheme.Color.forestSoft)
          .frame(width: 27, height: 27)
          .overlay {
            Image(systemName: "person.fill")
              .font(.caption2)
              .foregroundStyle(index.isMultiple(of: 2) ? MIRATheme.Color.auraViolet : MIRATheme.Color.forest)
          }
          .overlay { Circle().stroke(MIRATheme.Color.surface, lineWidth: 2) }
      }
    }
  }
}

struct AuraCommunityRemoteImage: View {
  let url: String?
  let height: CGFloat

  var body: some View {
    MIRACachedImage(url: url, maxPixelSize: max(400, height * 3)) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      ZStack {
        MIRATheme.Color.surfaceSoft
        Image(systemName: "photo")
          .font(.title2)
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
  }
}

public struct AuraMeetupDetailView: View {
  let api: MIRAAPIClient
  let post: AuraCommunityPost

  @State private var participants: AuraMeetupParticipantsResponse?
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var showPaidUnavailable = false

  public init(api: MIRAAPIClient, post: AuraCommunityPost) {
    self.api = api
    self.post = post
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        AuraCommunityRemoteImage(url: post.primaryImageURL, height: 270)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .physicalAuraCard(cornerRadius: 16)

        meetupSummary
        peopleSection
        joinButton

        if let errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 34)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationTitle("Meetup")
    .navigationBarTitleDisplayMode(.inline)
    .task { await loadParticipants() }
    .alert("Paid meetup joining unavailable", isPresented: $showPaidUnavailable) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Aura will not mark this meetup joined until an exact AUR payment is signed locally and confirmed by the real network. That payment-binding path is not enabled yet.")
    }
  }

  private var meetupSummary: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        Text(post.titleText)
          .font(.title2)
          .fontWeight(.black)
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Spacer()
        Text(post.entryLabel)
          .font(.subheadline)
          .fontWeight(.black)
          .foregroundStyle(MIRATheme.Color.auraViolet)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(MIRATheme.Color.auraVioletSoft, in: Capsule())
      }

      detailRow("mappin.and.ellipse", post.locationLine)
      detailRow("calendar", AuraCommunityFormatting.meetupDate(post.meetupStartsAt))
      detailRow("clock", AuraCommunityFormatting.meetupTimeRange(post.meetupStartsAt, post.meetupEndsAt))

      if !post.bodyText.isEmpty {
        Divider()
        Text(post.bodyText)
          .font(.body)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .physicalAuraCard()
  }

  private func detailRow(_ symbol: String, _ value: String) -> some View {
    Label(value, systemImage: symbol)
      .font(.subheadline)
      .foregroundStyle(MIRATheme.Color.textSecondary)
  }

  @ViewBuilder
  private var peopleSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("People Joining")
          .font(.headline)
        Spacer()
        if let count = participants?.joinedCount {
          Text("\(count) / \(post.meetupMaxPeople ?? 0)")
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      }

      if participants?.participants.isEmpty == false {
        ForEach(participants?.participants ?? []) { user in
          NavigationLink {
            UserProfileNativeView(userId: user.id, api: api)
          } label: {
            HStack(spacing: 11) {
              RemoteAvatar(url: user.profileImage, size: 38)
              VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                if MIRAUsernameRules.isValidPublicUsername(user.username) {
                  Text("@\(MIRAUsernameRules.normalized(user.username))")
                    .font(.caption)
                    .foregroundStyle(MIRATheme.Color.textMuted)
                }
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(MIRATheme.Color.textMuted)
            }
          }
          .buttonStyle(.plain)
        }
      } else if isLoading {
        ProgressView("Loading people…")
      } else {
        Text(post.meetupStateAvailable == false ? "Attendance is unavailable." : "No one has joined yet.")
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
    }
    .padding(16)
    .physicalAuraCard()
  }

  private var joinButton: some View {
    Button {
      if post.meetupEntryType?.lowercased() == AuraMeetupEntryType.aur.rawValue {
        showPaidUnavailable = true
      } else {
        Task { await toggleFreeJoin() }
      }
    } label: {
      HStack {
        if isLoading { ProgressView().tint(.white) }
        Text(joinButtonTitle)
          .font(.headline)
          .frame(maxWidth: .infinity)
      }
      .foregroundStyle(.white)
      .padding(.vertical, 15)
      .background(MIRATheme.Color.auraViolet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isLoading || post.meetupStateAvailable == false)
    .opacity(post.meetupStateAvailable == false ? 0.55 : 1)
  }

  private var joinButtonTitle: String {
    if participants?.viewerJoined == true { return "Leave Meetup" }
    if post.meetupEntryType?.lowercased() == AuraMeetupEntryType.aur.rawValue { return "Join for \(post.entryLabel)" }
    return "Join Meetup"
  }

  @MainActor
  private func loadParticipants() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      participants = try await api.get("/posts/\(post.id)/meetup/participants")
    } catch {
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not load meetup attendance."
    }
  }

  @MainActor
  private func toggleFreeJoin() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      if participants?.viewerJoined == true {
        let _: AuraMeetupJoinResponse = try await api.delete("/posts/\(post.id)/meetup/join")
      } else {
        let _: AuraMeetupJoinResponse = try await api.post(
          "/posts/\(post.id)/meetup/join",
          body: EmptyAuraCommunityBody()
        )
      }
      participants = try await api.get("/posts/\(post.id)/meetup/participants")
    } catch {
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not update meetup attendance."
    }
  }
}

private struct EmptyAuraCommunityBody: Encodable {}

@MainActor
final class AuraMyCommunityModel: ObservableObject {
  @Published var posts: [AuraCommunityPost] = []
  @Published var isLoading = false
  @Published var errorMessage: String?

  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load(scope: String) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      posts = try await api.get("/posts/community-mine?scope=\(scope)")
    } catch {
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not load community activity."
    }
  }
}

public struct AuraMyCommunityView: View {
  let api: MIRAAPIClient
  let scope: String
  let title: String
  @StateObject private var model: AuraMyCommunityModel

  public init(api: MIRAAPIClient, scope: String, title: String) {
    self.api = api
    self.scope = scope
    self.title = title
    _model = StateObject(wrappedValue: AuraMyCommunityModel(api: api))
  }

  public var body: some View {
    ScrollView {
      LazyVStack(spacing: 14) {
        if model.isLoading && model.posts.isEmpty {
          ProgressView("Loading…")
            .padding(.top, 40)
        } else if let error = model.errorMessage, model.posts.isEmpty {
          MIRAEmptyState(title: "Unavailable", message: error, systemImage: "person.3.sequence")
            .padding(.vertical, 30)
            .physicalAuraCard()
        } else if model.posts.isEmpty {
          MIRAEmptyState(
            title: scope == "joined" ? "No joined meetups" : "No community posts",
            message: scope == "joined" ? "Meetups you genuinely join will appear here." : "Small Posts and Meetups you publish will appear here.",
            systemImage: scope == "joined" ? "person.2" : "square.and.pencil"
          )
          .padding(.vertical, 30)
          .physicalAuraCard()
        } else {
          ForEach(model.posts) { post in
            if post.mode == .meetup {
              NavigationLink {
                AuraMeetupDetailView(api: api, post: post)
              } label: {
                AuraMeetupFeedCard(post: post)
              }
              .buttonStyle(.plain)
            } else {
              NavigationLink {
                AuraSmallPostDetailLoaderView(api: api, postID: post.id)
              } label: {
                AuraSmallPostFeedCard(post: post)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .padding(16)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load(scope: scope) }
    .refreshable { await model.load(scope: scope) }
  }
}

enum AuraCommunityFormatting {
  static func date(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  static func relativeDate(_ value: String?) -> String {
    guard let date = date(value) else { return "" }
    return date.formatted(.relative(presentation: .numeric))
  }

  static func meetupDate(_ value: String?) -> String {
    guard let date = date(value) else { return "Date unavailable" }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  static func meetupTimeRange(_ start: String?, _ end: String?) -> String {
    guard let startDate = date(start), let endDate = date(end) else { return "Time unavailable" }
    return "\(startDate.formatted(date: .omitted, time: .shortened)) – \(endDate.formatted(date: .omitted, time: .shortened))"
  }
}
