import SwiftUI

struct ClubChatLinkMessage: View {
  let url: URL
  let api: MIRAAPIClient
  @State private var post: MIRAPost?
  @State private var confirmExternalOpen = false
  @Environment(\.openURL) private var openURL

  private var postId: String? {
    guard url.host?.lowercased() == MIRAProductionBackend.siteURL("post").host?.lowercased() else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count == 2, parts[0] == "post", !parts[1].isEmpty else { return nil }
    return parts[1]
  }

  var body: some View {
    Group {
      if let postId {
        if let post {
          NavigationLink(destination: DiscoverPostDetailNativeView(post: post, api: api)) {
            preview(post)
          }
          .buttonStyle(.plain)
        } else {
          Text("Captro post unavailable")
            .font(.system(size: 13))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .padding(12)
            .task(id: postId) {
              post = try? await api.get("/posts/\(postId)")
            }
        }
      } else {
        Button {
          confirmExternalOpen = true
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(url.host ?? "Website")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .lineLimit(1)
            Text(url.absoluteString)
              .font(.system(size: 12))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .lineLimit(2)
            Text("Open ↗")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textPrimary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Open external link?", isPresented: $confirmExternalOpen) {
          Button("Open \(url.host ?? "website")") { openURL(url) }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(url.absoluteString)
        }
      }
    }
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10).stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
    .frame(maxWidth: 264)
  }

  private func preview(_ post: MIRAPost) -> some View {
    HStack(spacing: 10) {
      if let media = post.feedMediaURLs.first, !media.isVideoURL {
        RemoteMediaView(url: media, isVideo: false, maxPixelSize: 160)
          .frame(width: 54, height: 54)
          .clipped()
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(post.titleText.isEmpty ? "Captro post" : post.titleText)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)
        Text(post.userUsername.map { "@\($0)" } ?? "Open post")
          .font(.system(size: 11))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct ClubChatHeader: View {
  let title: String
  let info: MIRAGroupInfo?
  let onBack: () -> Void
  let onMore: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.system(size: 19, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Back")

      VStack(alignment: .leading, spacing: 3) {
        Text(info?.name ?? title)
          .font(.system(size: 20, weight: .bold))
          .lineLimit(1)
        Text(memberSummary)
          .font(.system(size: 12))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onMore) {
        Image(systemName: "ellipsis")
          .font(.system(size: 19, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Club chat options")
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .frame(minHeight: 62)
    .background(MIRATheme.Color.surface)
  }

  private var memberSummary: String {
    guard let count = info?.memberCount else { return "Club conversation" }
    if let active = info?.activeCount {
      return "\(count) members · \(active) active"
    }
    return "\(count) members"
  }
}

struct ClubMemberAvatarRow: View {
  let info: MIRAGroupInfo
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: -7) {
        ForEach(Array((info.members ?? []).prefix(4))) { member in
          RemoteAvatar(url: member.profileImage, size: 34)
            .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
        }
        let remainder = max(0, (info.memberCount ?? info.members?.count ?? 0) - 4)
        if remainder > 0 {
          Text("+\(remainder)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 34, height: 34)
            .background(MIRATheme.Color.surfaceSoft, in: Circle())
            .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
        }
        Spacer(minLength: 0)
        Text("Members")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      .frame(height: 42)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 18)
    .accessibilityLabel("View \(info.memberCount ?? info.members?.count ?? 0) club members")
  }
}

struct ActiveClubActivityCard: View {
  let activity: MIRAClubActivity
  let onView: () -> Void

  var body: some View {
    Button(action: onView) {
      HStack(spacing: 12) {
        if let image = activity.imageUrl, !image.isEmpty {
          RemoteMediaView(
            url: image,
            isVideo: false,
            maxPixelSize: 180,
            placeholderColor: MIRATheme.Color.surfaceSoft
          )
          .frame(width: 56, height: 56)
          .clipped()
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(activity.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
          if let subtitle = activity.subtitle {
            Text(subtitle)
              .font(.system(size: 12))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .lineLimit(2)
          }
          if let detail = activity.detail {
            Text(detail)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textMuted)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text("View")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MIRATheme.Color.surface)
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(MIRATheme.Color.hairline, lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
    .accessibilityLabel("Current club activity, \(activity.title). View details")
  }
}

struct ClubPinnedMessageRow: View {
  let message: String
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 9) {
        Image(systemName: "pin")
          .font(.system(size: 12))
        Text("1 pinned")
          .font(.system(size: 12, weight: .semibold))
        Text("·")
        Text(message)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
      }
      .font(.system(size: 12))
      .foregroundStyle(MIRATheme.Color.textSecondary)
      .padding(.horizontal, 18)
      .frame(height: 42)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("View pinned message: \(message)")
  }
}

struct ClubMembersSheet: View {
  let members: [MIRAGroupMember]
  let api: MIRAAPIClient

  var body: some View {
    NavigationStack {
      List(members) { member in
        NavigationLink(destination: UserProfileNativeView(userId: member.id, api: api)) {
          HStack(spacing: 12) {
            RemoteAvatar(url: member.profileImage, size: 40)
            VStack(alignment: .leading, spacing: 2) {
              Text(member.displayName)
                .font(.system(size: 15, weight: .semibold))
              if let username = member.username {
                Text("@\(username)")
                  .font(.system(size: 12))
                  .foregroundStyle(MIRATheme.Color.textSecondary)
              }
            }
            Spacer()
            if member.role == "owner" || member.role == "admin" {
              Text(member.role == "owner" ? "HOST" : "MOD")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textSecondary)
            }
          }
        }
      }
      .navigationTitle("Members")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
struct ClubPostShareSheet: View {
  let api: MIRAAPIClient
  let userId: String
  let onSelect: (MIRAPost) -> Void
  @State private var posts: [MIRAPost] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Loading your posts")
        } else if let errorMessage {
          ContentUnavailableView("Posts unavailable", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
        } else if posts.isEmpty {
          ContentUnavailableView("No posts to share", systemImage: "photo", description: Text("Create a Captro post first."))
        } else {
          List(posts) { post in
            Button {
              onSelect(post)
            } label: {
              HStack(spacing: 12) {
                if let media = post.feedMediaURLs.first, !media.isVideoURL {
                  RemoteMediaView(url: media, isVideo: false, maxPixelSize: 160)
                    .frame(width: 46, height: 46)
                    .clipped()
                }
                Text(post.titleText.isEmpty ? "Post" : post.titleText)
                  .font(.system(size: 14, weight: .medium))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                  .lineLimit(2)
              }
            }
          }
        }
      }
      .navigationTitle("Share Captro post")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        guard !userId.isEmpty else {
          isLoading = false
          errorMessage = "Sign in to share a post."
          return
        }
        do {
          posts = try await api.get("/users/\(userId)/posts")
        } catch {
          errorMessage = "Could not load your posts. Try again later."
        }
        isLoading = false
      }
    }
  }
}
#if DEBUG
private struct ClubChatDesignPreview: View {
  private let info = MIRAGroupInfo(
    id: "preview-club",
    name: "NYC Photo Club",
    createdBy: "host",
    memberCount: 127,
    activeCount: 18,
    members: [
      MIRAGroupMember(id: "host", username: "karfala", fullName: "Karfala", profileImage: nil, role: "owner"),
      MIRAGroupMember(id: "maya", username: "maya", fullName: "Maya", profileImage: nil, role: "member"),
      MIRAGroupMember(id: "jay", username: "jay", fullName: "Jay", profileImage: nil, role: "member"),
      MIRAGroupMember(id: "leo", username: "leo", fullName: "Leo", profileImage: nil, role: "member")
    ],
    activity: MIRAClubActivity(
      title: "SATURDAY PHOTO WALK",
      subtitle: "SoHo · Sep 26 · 2 PM",
      detail: "12 going",
      imageUrl: nil,
      destinationType: "meetup",
      destinationId: "preview"
    ),
    pinnedMessage: "Meet outside the café at 1:50 PM"
  )

  var body: some View {
    VStack(spacing: 0) {
      ClubChatHeader(title: "NYC Photo Club", info: info, onBack: {}, onMore: {})
      ClubMemberAvatarRow(info: info, onTap: {})
      ActiveClubActivityCard(activity: info.activity!, onView: {})
        .padding(.vertical, 8)
      ClubPinnedMessageRow(message: info.pinnedMessage!, onTap: {})
      Divider()
      VStack(alignment: .leading, spacing: 20) {
        previewMessage("Maya", "10:14 AM", "Anyone shooting film this weekend?")
        previewMessage("Jay", "10:16 AM", "I'm down for Saturday.")
        HStack {
          Spacer()
          VStack(alignment: .trailing, spacing: 5) {
            Text("You  10:17 AM").font(.caption).foregroundStyle(.secondary)
            Text("Same. Around 2?")
              .padding(12)
              .background(Color(red: 0.94, green: 0.95, blue: 0.94), in: RoundedRectangle(cornerRadius: 12))
          }
        }
        Spacer()
      }
      .padding(18)
      HStack {
        Image(systemName: "plus")
        Text("Message the club...").foregroundStyle(.secondary)
        Spacer()
        Image(systemName: "mic")
      }
      .padding(14)
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.25)))
      .padding(14)
    }
    .background(.white)
  }

  private func previewMessage(_ name: String, _ time: String, _ text: String) -> some View {
    HStack(alignment: .bottom, spacing: 10) {
      Circle().fill(.gray.opacity(0.18)).frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 5) {
        Text("\(name)  \(time)").font(.caption).foregroundStyle(.secondary)
        Text(text)
          .padding(12)
          .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 12))
      }
      Spacer()
    }
  }
}

#Preview("Club chat") {
  ClubChatDesignPreview()
}
#endif
