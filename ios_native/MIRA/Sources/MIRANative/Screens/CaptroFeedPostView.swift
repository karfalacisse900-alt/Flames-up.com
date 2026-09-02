import Foundation
import SwiftUI

struct CaptroFeedPostView: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  let showsFeedControls: Bool
  let onFollow: () async -> Bool
  let onOpenOptions: () -> Void
  let onCreate: () -> Void
  let onOpenPost: () -> Void
  let canFollowAuthor: Bool
  let pageSize: CGSize?
  @Binding var selectedMediaIndex: Int
  let showsCoverMediaOnly: Bool

  @Environment(\.displayScale) private var displayScale

  var body: some View {
    Group {
      if let pageSize {
        postContent
          .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
          .clipped()
      } else {
        postContent
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onChange(of: post.id) { _, _ in
      selectedMediaIndex = 0
    }
  }

  private var postContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !post.feedMediaURLs.isEmpty {
        mediaPager
      } else {
        CaptroPostStamp(content: post.captroStampContent, onOpen: onOpenPost)
          .padding(.horizontal, 16)
      }

      if showsMoreButton {
        HStack {
          Spacer(minLength: 0)
          Button("More", action: onOpenPost)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityHint("Opens the full post")
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
      }

      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 1 / max(displayScale, 1))
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var mediaPager: some View {
    let pager = CaptroMediaPager(
      post: post,
      isVideoActive: isVideoActive,
      selectedMediaIndex: $selectedMediaIndex,
      onOpenPost: onOpenPost,
      showsCoverMediaOnly: showsCoverMediaOnly
    )

    if let mediaSize = pageMediaSize {
      pager
        .frame(width: mediaSize.width, height: mediaSize.height)
        .frame(maxWidth: .infinity, alignment: .center)
    } else {
      pager
        .frame(maxWidth: .infinity)
    }
  }

  private var pageMediaSize: CGSize? {
    guard let pageSize, !post.feedMediaURLs.isEmpty else { return nil }
    let ratio = MIRAMediaSizing.supportedPostHeightToWidthRatio(
      post.mediaDimensions?.values.first?.heightToWidthRatio
        ?? MIRAMediaSizing.mainFeedDisplayRatio(for: post.feedMediaURLs, aspectRatios: post.mediaHeightToWidthRatios)
    )
    let fixedVerticalContent: CGFloat = 25 + (showsMoreButton ? 44 : 0)
    let availableMediaHeight = max(120, pageSize.height - fixedVerticalContent)
    let width = min(pageSize.width, availableMediaHeight / max(ratio, 0.01))
    return CGSize(width: width, height: width * ratio)
  }

  private var showsMoreButton: Bool {
    if post.containsVideoMedia { return true }
    guard let caption = post.captroFeedCaptionText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return false
    }
    return caption.count > 110 || caption.split(separator: "\n", omittingEmptySubsequences: false).count > 3
  }
}

private struct CaptroAuthorHeader: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let showsFeedControls: Bool
  let canFollowAuthor: Bool
  let onFollow: () async -> Bool
  let onCreate: () -> Void
  let onOpenOptions: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isSubmittingFollow = false
  @State private var isFollowConfirmationVisible = false

  var body: some View {
    HStack(spacing: 10) {
      authorAvatar

      authorIdentity
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

      if post.isPinned {
        Image(systemName: "pin.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(width: 32, height: 44)
          .accessibilityLabel("Pinned post")
      }

      if showsFeedControls {
        Button(action: onCreate) {
          MIRAHeaderCircleButton(systemImage: "plus")
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel("Create post")

        NavigationLink(destination: NotificationNativeView(api: api)) {
          MIRAHeaderCircleButton(systemImage: "bell")
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel("Notifications")
      }

      Button {
        CaptroHaptics.light()
        onOpenOptions()
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)
      .accessibilityLabel("Post options")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .overlay(alignment: .bottomLeading) {
      if isFollowConfirmationVisible {
        Label("Following", systemImage: "checkmark")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .background(MIRATheme.Color.forest.opacity(0.94))
          .clipShape(Capsule())
          .offset(x: 64, y: 16)
          .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
          .allowsHitTesting(false)
      }
    }
    .zIndex(4)
  }

  @ViewBuilder
  private var authorAvatar: some View {
    if canFollowAuthor || isSubmittingFollow || isFollowConfirmationVisible {
      Button(action: followWithConfirmation) {
        MIRAFollowAvatar(
          url: post.userProfileImage,
          size: 46,
          isFollowing: post.viewerFollowing || isSubmittingFollow || isFollowConfirmationVisible
        )
        .scaleEffect(isFollowConfirmationVisible ? 1.05 : 1)
      }
      .buttonStyle(.plain)
      .disabled(isSubmittingFollow)
      .frame(width: 46, height: 46)
      .contentShape(Circle())
      .accessibilityLabel(isSubmittingFollow || isFollowConfirmationVisible ? "Following" : "Follow \(post.authorDisplayName)")
    } else if let userId = post.userId, !userId.isEmpty {
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api).miraHideTabBarOnAppear()) {
        RemoteAvatar(url: post.userProfileImage, size: 46)
      }
      .buttonStyle(.plain)
      .frame(width: 46, height: 46)
      .contentShape(Circle())
      .accessibilityLabel("View \(post.authorDisplayName)'s profile")
    } else {
      RemoteAvatar(url: post.userProfileImage, size: 46)
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var authorIdentity: some View {
    if let userId = post.userId, !userId.isEmpty {
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api).miraHideTabBarOnAppear()) {
        authorIdentityLabel
      }
      .buttonStyle(.plain)
      .frame(minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    } else {
      authorIdentityLabel
        .frame(minHeight: 44, alignment: .leading)
    }
  }

  private var authorIdentityLabel: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(post.authorDisplayName)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func followWithConfirmation() {
    guard !isSubmittingFollow, canFollowAuthor else { return }
    CaptroHaptics.light()
    isSubmittingFollow = true
    withAnimation(CaptroMotion.buttonPressAnimation(reduceMotion: reduceMotion)) {
      isFollowConfirmationVisible = true
    }

    Task {
      let didFollow = await onFollow()
      try? await Task.sleep(nanoseconds: didFollow ? 1_050_000_000 : 180_000_000)
      await MainActor.run {
        withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
          isFollowConfirmationVisible = false
        }
        isSubmittingFollow = false
      }
    }
  }
}
