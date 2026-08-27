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

private struct AuraEditorialAvatarRail: View {
  let avatarURL: String?

  var body: some View {
    RemoteAvatar(url: avatarURL, size: 48)
      .overlay(alignment: .bottomTrailing) {
        // The feed projection does not expose a follow mutation. Keep the reference's compact
        // profile affordance visual-only instead of pretending a tap followed the member.
        Image(systemName: "plus")
          .font(.caption.weight(.black))
          .foregroundStyle(Color.white)
          .frame(width: 23, height: 23)
          .background(AuraFeedPalette.ink, in: Circle())
          .overlay { Circle().stroke(AuraFeedPalette.card, lineWidth: 2) }
          .offset(x: 2, y: 2)
          .accessibilityHidden(true)
      }
      .frame(width: 52, alignment: .top)
  }
}

private struct AuraEditorialStatusBadge: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      .font(.caption2.weight(.black))
      .foregroundStyle(MIRATheme.Color.auraViolet)
      .frame(width: 19, height: 19)
      .background(MIRATheme.Color.auraVioletSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
      .accessibilityHidden(true)
  }
}

private struct AuraEditorialPostHeader: View {
  let post: AuraCommunityPost
  let status: String
  let symbol: String

  var body: some View {
    HStack(spacing: 6) {
      Text(post.authorHandle)
        .font(.headline)
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
      AuraEditorialStatusBadge(symbol: symbol)
      Text(status)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .lineLimit(1)
      Text("·")
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text(AuraCommunityFormatting.relativeDate(post.createdAt))
        .font(.subheadline)
        .foregroundStyle(MIRATheme.Color.textMuted)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }
}

private struct AuraEditorialAttachmentRow: View {
  let post: AuraCommunityPost

  var body: some View {
    HStack(spacing: 0) {
      attachmentThumbnail
        .frame(width: 72, height: 72)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)

        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .lineLimit(1)
        }

        if let detail {
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, alignment: .leading)

      // Saving is not part of the community feed projection yet. This preserves the requested
      // visual target without introducing a no-op button or a fabricated saved state.
      Image(systemName: "bookmark")
        .font(.body.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .frame(width: 36, height: 36)
        .background(AuraFeedPalette.card, in: Circle())
        .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 2)
        .padding(.trailing, 10)
        .accessibilityHidden(true)
    }
    .frame(minHeight: 72)
    .background(AuraFeedPalette.card)
    .overlay {
      Rectangle().stroke(Color(uiColor: .separator), lineWidth: 1)
    }
  }

  @ViewBuilder
  private var attachmentThumbnail: some View {
    if let url = post.auraEditorialPhotoURLs.first ?? post.primaryImageURL {
      AuraCommunityRemoteImage(url: url, height: 72)
    } else {
      ZStack {
        AuraFeedPalette.muted
        Image(systemName: "mappin.and.ellipse")
          .font(.title3.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.auraViolet)
      }
    }
  }

  private var title: String {
    post.auraEditorialAttachmentValues.first ?? "Place"
  }

  private var subtitle: String? {
    post.auraEditorialAttachmentValues.dropFirst().first
  }

  private var detail: String? {
    post.auraEditorialAttachmentValues.dropFirst(2).first
  }
}

private struct AuraEditorialMediaGallery: View {
  let post: AuraCommunityPost

  private let mediaHeight: CGFloat = 252

  // AuraCommunityPost currently has no explicit editorial-feature signal. Media count,
  // engagement, and feed position must not be used to invent a hero/featured treatment.

  @ViewBuilder
  var body: some View {
    let urls = post.auraEditorialPhotoURLs
    if urls.count >= 2 {
      HStack(spacing: 3) {
        editorialPhoto(urls[0])
        editorialPhoto(urls[1])
          .overlay(alignment: .bottomTrailing) {
            if urls.count > 2 {
              Text("+\(urls.count - 2)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.72), in: Capsule())
                .padding(8)
            }
          }
      }
    } else if let url = urls.first {
      editorialPhoto(url)
    } else if post.primaryMediaType == "video", post.primaryImageURL != nil {
      AuraCommunityPostMedia(post: post, height: mediaHeight)
    }
  }

  private func editorialPhoto(_ url: String) -> some View {
    AuraCommunityRemoteImage(url: url, height: mediaHeight)
      .frame(maxWidth: .infinity)
  }
}

private struct AuraEditorialFeedbackRow: View {
  let post: AuraCommunityPost

  var body: some View {
    HStack(spacing: 16) {
      Spacer(minLength: 0)
      HStack(spacing: 5) {
        Image(systemName: post.communityAllowReplies == false ? "bubble.left.and.exclamationmark.bubble.right" : "bubble.left")
        if let count = post.commentsCount, count > 0 {
          Text("\(count)")
        }
      }
      Image(systemName: "heart")
        .accessibilityHidden(true)
    }
    .font(.body.weight(.medium))
    .foregroundStyle(MIRATheme.Color.textMuted)
    .accessibilityLabel(replyLabel)
  }

  private var replyLabel: String {
    if post.communityAllowReplies == false { return "Replies off" }
    return post.commentsCount.map { "\($0) replies" } ?? "Replies"
  }
}

private extension AuraCommunityPost {
  var auraEditorialPhotoURLs: [String] {
    let preferred = (feedMediaUrls ?? []).isEmpty
      ? (images ?? []) + [image ?? ""]
      : (feedMediaUrls ?? [])
    var seen = Set<String>()
    var photos: [String] = []

    for (index, rawValue) in preferred.enumerated() {
      let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      let lowercased = value.lowercased()
      let declaredType = (mediaTypes?.indices.contains(index) == true)
        ? mediaTypes?[index].lowercased()
        : nil
      let isVideo = declaredType == "video"
        || lowercased.hasPrefix("cfstream:")
        || lowercased.contains("videodelivery.net/")
        || lowercased.contains("cloudflarestream.com/")
        || lowercased.contains(".m3u8")
      guard !isVideo, seen.insert(value).inserted else { continue }
      photos.append(value)
    }

    if photos.isEmpty, primaryMediaType != "video", let primaryImageURL {
      photos.append(primaryImageURL)
    }
    return photos
  }

  var auraEditorialAttachmentValues: [String] {
    let candidates = [
      placeName,
      displayLocationLabel,
      placeFormattedAddress,
      meetupNeighborhood,
      displayCity,
      location,
    ]
    var normalized = Set<String>()
    return candidates.compactMap { candidate in
      guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
      }
      let key = value.lowercased()
      guard normalized.insert(key).inserted else { return nil }
      return value
    }
  }

  var auraEditorialStatus: String {
    let value = communityCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? "posted" : value.lowercased()
  }

  var auraEditorialStatusSymbol: String {
    switch communityCategory?.lowercased() {
    case "question": return "questionmark"
    case "idea": return "lightbulb.fill"
    case "concern": return "exclamationmark"
    case "recommendation": return "hand.thumbsup.fill"
    case "update": return "megaphone.fill"
    default: return "sparkle"
    }
  }

  var hasAuraEditorialAttachment: Bool {
    !auraEditorialAttachmentValues.isEmpty
  }
}

public struct AuraSmallPostFeedCard: View {
  let post: AuraCommunityPost

  public init(post: AuraCommunityPost) {
    self.post = post
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      AuraEditorialAvatarRail(avatarURL: post.userProfileImage)

      VStack(alignment: .leading, spacing: 11) {
        AuraEditorialPostHeader(
          post: post,
          status: post.auraEditorialStatus,
          symbol: post.auraEditorialStatusSymbol
        )

        if !post.titleText.isEmpty {
          Text(post.titleText)
            .font(.headline)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !post.bodyText.isEmpty {
          Text(post.bodyText)
            .font(.body)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if post.hasAuraEditorialAttachment {
          AuraEditorialAttachmentRow(post: post)
        }

        if post.primaryImageURL != nil || !post.auraEditorialPhotoURLs.isEmpty {
          AuraEditorialMediaGallery(post: post)
        }

        AuraEditorialFeedbackRow(post: post)
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 14)
    .background(Color.clear)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color(uiColor: .separator))
        .frame(height: 0.5)
    }
    .accessibilityElement(children: .contain)
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

public struct AuraMeetupFeedCard: View {
  let post: AuraCommunityPost

  public init(post: AuraCommunityPost) {
    self.post = post
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      AuraEditorialAvatarRail(avatarURL: post.userProfileImage)

      VStack(alignment: .leading, spacing: 11) {
        AuraEditorialPostHeader(post: post, status: "meetup", symbol: "person.3.fill")

        Text(post.titleText)
          .font(.title3)
          .fontWeight(.black)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)

        if !post.bodyText.isEmpty {
          Text(post.bodyText)
            .font(.body)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if post.hasAuraEditorialAttachment {
          AuraEditorialAttachmentRow(post: post)
        }

        if post.primaryImageURL != nil || !post.auraEditorialPhotoURLs.isEmpty {
          AuraEditorialMediaGallery(post: post)
        }

        meetupMetadata
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 14)
    .background(Color.clear)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color(uiColor: .separator))
        .frame(height: 0.5)
    }
    .accessibilityElement(children: .contain)
  }

  private var meetupMetadata: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        Label(AuraCommunityFormatting.meetupDate(post.meetupStartsAt), systemImage: "calendar")
          .lineLimit(1)
        Spacer(minLength: 4)
        entryPill
      }

      HStack(spacing: 8) {
        AuraStackedProfilePlaceholders(count: max(0, min(post.meetupJoinedCount ?? 0, 4)))
        Text(attendanceLabel)
        Spacer(minLength: 0)
      }
    }
    .font(.footnote.weight(.semibold))
    .foregroundStyle(MIRATheme.Color.textSecondary)
  }

  private var entryPill: some View {
    Text(post.entryLabel)
      .font(.caption.weight(.black))
      .foregroundStyle(post.meetupEntryType == "aur" ? MIRATheme.Color.auraViolet : MIRATheme.Color.forest)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(post.meetupEntryType == "aur" ? MIRATheme.Color.auraVioletSoft : MIRATheme.Color.forestSoft, in: Capsule())
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
