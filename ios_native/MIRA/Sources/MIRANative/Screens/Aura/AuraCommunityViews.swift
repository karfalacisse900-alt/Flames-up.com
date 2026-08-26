import SwiftUI
import UIKit

enum AuraFeedPalette {
  static let canvas = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.055, green: 0.057, blue: 0.052, alpha: 1)
      : UIColor(red: 0.969, green: 0.965, blue: 0.953, alpha: 1)
  })
  static let card = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.090, green: 0.094, blue: 0.083, alpha: 1)
      : UIColor(red: 0.997, green: 0.995, blue: 0.989, alpha: 1)
  })
  static let muted = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.125, green: 0.130, blue: 0.115, alpha: 1)
      : UIColor(red: 0.925, green: 0.920, blue: 0.904, alpha: 1)
  })
  static let ink = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.910, green: 0.905, blue: 0.875, alpha: 1)
      : UIColor(red: 0.090, green: 0.098, blue: 0.078, alpha: 1)
  })
  static let shadow = Color.black.opacity(0.84)
}

public extension View {
  func physicalAuraCard(cornerRadius: CGFloat = 14) -> some View {
    modifier(PhysicalAuraCardModifier(cornerRadius: cornerRadius))
  }

  func auraFeedCard(cornerRadius: CGFloat = 13, shadowOffset: CGFloat = 5) -> some View {
    modifier(AuraFeedCardModifier(cornerRadius: cornerRadius, shadowOffset: shadowOffset))
  }
}

private struct AuraFeedCardModifier: ViewModifier {
  let cornerRadius: CGFloat
  let shadowOffset: CGFloat

  func body(content: Content) -> some View {
    content
      .background(AuraFeedPalette.card)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(AuraFeedPalette.ink, lineWidth: 1.25)
      }
      .shadow(color: AuraFeedPalette.shadow, radius: 0, x: 0, y: shadowOffset)
      .padding(.bottom, shadowOffset)
  }
}

private struct PhysicalAuraCardModifier: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(MIRATheme.Color.paperSurface)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(MIRATheme.Color.inkBorder, lineWidth: 1.25)
      }
      .shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 3)
      .padding(.bottom, 3)
  }
}

private enum AuraSmallPostCardVariant: Equatable {
  case micro
  case small
  case smallWithImage
}

public struct AuraSmallPostFeedCard: View {
  let post: AuraCommunityPost

  public init(post: AuraCommunityPost) {
    self.post = post
  }

  @ViewBuilder
  public var body: some View {
    switch variant {
    case .micro:
      microCard
    case .small, .smallWithImage:
      smallCard
    }
  }

  private var variant: AuraSmallPostCardVariant {
    if post.primaryImageURL != nil { return .smallWithImage }
    if post.titleText.isEmpty && post.bodyText.count <= 120 { return .micro }
    return .small
  }

  private var microCard: some View {
    HStack(alignment: .top, spacing: 9) {
      RemoteAvatar(url: post.userProfileImage, size: 30)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(post.authorHandle)
            .font(.system(size: 13.5, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
          categoryPill
          Spacer(minLength: 3)
          timestamp
        }

        Text(post.bodyText)
          .font(.system(size: 13.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)

        if let commentsCount = post.commentsCount, commentsCount > 0 {
          Text("\(commentsCount) replies")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
    }
    .padding(10)
    .auraFeedCard(cornerRadius: 12, shadowOffset: 4)
    .accessibilityElement(children: .combine)
  }

  private var smallCard: some View {
    HStack(alignment: .top, spacing: 10) {
      RemoteAvatar(url: post.userProfileImage, size: 34)

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 7) {
          Text(post.authorHandle)
            .font(.system(size: 14, weight: .bold))
            .fontWeight(.bold)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
          categoryPill
          Spacer(minLength: 4)
          timestamp
        }

        if !post.titleText.isEmpty {
          Text(post.titleText)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(2)
        }

        HStack(alignment: .top, spacing: 10) {
          if !post.bodyText.isEmpty {
            Text(post.bodyText)
              .font(.system(size: 14))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .lineLimit(3)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          if variant == .smallWithImage {
            AuraCommunityPostMedia(post: post, height: 64)
              .frame(width: 70)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .stroke(MIRATheme.Color.inkBorder.opacity(0.72), lineWidth: 1)
              }
          }
        }

        if post.communityAllowReplies != false {
          Label(replyLabel, systemImage: "bubble.left")
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
    .padding(12)
    .auraFeedCard(cornerRadius: 13, shadowOffset: 5)
    .accessibilityElement(children: .combine)
  }

  private var categoryPill: some View {
    Text(post.communityCategory?.uppercased() ?? "POST")
      .font(.system(size: 9.5, weight: .black))
      .foregroundStyle(MIRATheme.Color.auraViolet)
      .padding(.horizontal, 6)
      .padding(.vertical, 2.5)
      .background(MIRATheme.Color.auraVioletSoft, in: Capsule())
  }

  private var timestamp: some View {
    Text(AuraCommunityFormatting.relativeDate(post.createdAt))
      .font(.caption2)
      .foregroundStyle(MIRATheme.Color.textMuted)
  }

  private var replyLabel: String {
    post.commentsCount.map { "\($0) replies" } ?? "Replies"
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
    .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
    .task {
      if model.post == nil { await model.load() }
    }
  }
}

private enum AuraMeetupCardVariant: Equatable {
  case compactWithImage
  case compactWithoutImage
}

public struct AuraMeetupFeedCard: View {
  let post: AuraCommunityPost

  public init(post: AuraCommunityPost) {
    self.post = post
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 11) {
      meetupThumbnail

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 6) {
          meetupPill
          Spacer(minLength: 4)
          entryPill
        }

        Text(post.titleText)
          .font(.headline)
          .fontWeight(.black)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)

        Label(post.locationLine, systemImage: "mappin.and.ellipse")
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)

        HStack(spacing: 5) {
          Image(systemName: "calendar")
          Text(AuraCommunityFormatting.meetupDate(post.meetupStartsAt))
            .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)

        HStack(spacing: 7) {
          AuraStackedProfilePlaceholders(count: max(0, min(post.meetupJoinedCount ?? 0, 4)))
          Text(attendanceLabel)
            .font(.caption2)
            .foregroundStyle(MIRATheme.Color.textSecondary)
          Spacer(minLength: 0)
        }
      }
      .padding(.vertical, 2)
    }
    .padding(10)
    .auraFeedCard(cornerRadius: 14, shadowOffset: 5)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var meetupThumbnail: some View {
    switch variant {
    case .compactWithImage:
      AuraCommunityPostMedia(post: post, height: 104)
        .frame(width: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AuraFeedPalette.ink.opacity(0.72), lineWidth: 1)
        }
    case .compactWithoutImage:
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(AuraFeedPalette.muted)
        Image(systemName: "calendar.badge.plus")
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(MIRATheme.Color.auraViolet)
      }
      .frame(width: 72, height: 96)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(AuraFeedPalette.ink.opacity(0.48), lineWidth: 1)
      }
    }
  }

  private var meetupPill: some View {
    Text("MEETUP")
      .font(.system(size: 9.5, weight: .black))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(AuraFeedPalette.card, in: Capsule())
      .overlay { Capsule().stroke(AuraFeedPalette.ink, lineWidth: 1) }
  }

  private var entryPill: some View {
    Text(post.entryLabel)
      .font(.caption2)
      .fontWeight(.black)
      .foregroundStyle(post.meetupEntryType == "aur" ? MIRATheme.Color.auraViolet : MIRATheme.Color.forest)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(post.meetupEntryType == "aur" ? MIRATheme.Color.auraVioletSoft : MIRATheme.Color.forestSoft, in: Capsule())
      .overlay {
        Capsule().stroke(AuraFeedPalette.ink.opacity(0.72), lineWidth: 1)
      }
  }

  private var variant: AuraMeetupCardVariant {
    post.primaryImageURL == nil ? .compactWithoutImage : .compactWithImage
  }

  private var attendanceLabel: String {
    guard post.meetupStateAvailable != false, let count = post.meetupJoinedCount else { return "Attendance unavailable" }
    return "\(count) going"
  }
}

struct AuraStackedProfilePlaceholders: View {
  let count: Int

  var body: some View {
    // The feed projection exposes a canonical joined count, not participant identities. These
    // overlapping silhouettes visualize only that bounded count and never invent names or photos.
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
          .overlay { Circle().stroke(AuraFeedPalette.card, lineWidth: 2) }
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
        AuraFeedPalette.muted
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

/// Uses a lightweight Cloudflare poster in scrolling feeds and resolves the real Stream
/// playback URL only on a detail screen. Photos continue through the cached image path.
private struct AuraCommunityPostMedia: View {
  let post: AuraCommunityPost
  let height: CGFloat
  var playsVideo = false

  var body: some View {
    Group {
      if post.primaryMediaType == "video", playsVideo, let playbackURL = post.primaryPlaybackURL {
        RemoteMediaView(
          url: playbackURL,
          isVideo: true,
          placeholderURL: post.primaryPosterURL,
          contentMode: .fill,
          shouldPlay: true,
          videoMuted: false,
          maxPixelSize: max(height * 3, 720),
          showsVideoPlaceholderIcon: true,
          placeholderColor: MIRATheme.Color.paperSurfaceMuted,
          placeholderTint: MIRATheme.Color.inkBorder
        )
      } else {
        AuraCommunityRemoteImage(url: post.primaryImageURL, height: height)
          .overlay {
            if post.primaryMediaType == "video" {
              Image(systemName: "play.fill")
                .font(.system(size: height < 100 ? 13 : 20, weight: .black))
                .foregroundStyle(MIRATheme.Color.paperSurface)
                .frame(width: height < 100 ? 30 : 46, height: height < 100 ? 30 : 46)
                .background(MIRATheme.Color.inkBorder.opacity(0.88), in: Circle())
                .accessibilityHidden(true)
            }
          }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .accessibilityLabel(post.primaryMediaType == "video" ? "Video" : "Photo")
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
        AuraCommunityPostMedia(post: post, height: 270, playsVideo: true)
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
    .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
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
    .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
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
