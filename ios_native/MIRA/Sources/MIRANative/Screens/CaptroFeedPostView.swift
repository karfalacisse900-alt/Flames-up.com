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

  @Environment(\.displayScale) private var displayScale
  @State private var selectedMediaIndex = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      CaptroAuthorHeader(
        post: post,
        api: api,
        showsFeedControls: showsFeedControls,
        canFollowAuthor: canFollowAuthor,
        onFollow: onFollow,
        onCreate: onCreate,
        onOpenOptions: onOpenOptions
      )

      if !post.feedMediaURLs.isEmpty {
        CaptroMediaPager(
          post: post,
          isVideoActive: isVideoActive,
          selectedMediaIndex: $selectedMediaIndex,
          onOpenPost: onOpenPost
        )
        .containerRelativeFrame(.horizontal)
      } else {
        CaptroPostStamp(content: post.captroStampContent, onOpen: onOpenPost)
          .padding(.horizontal, 16)
      }

      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 1 / max(displayScale, 1))
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .containerRelativeFrame(.horizontal, alignment: .leading)
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: CaptroFeedPostVisibilityPreferenceKey.self,
          value: [
            CaptroFeedPostVisibility(
              id: post.id,
              visibleRatio: visibleRatio(in: proxy),
              hasVideo: post.feedMediaURLs.contains { $0.isVideoURL }
            )
          ]
        )
      }
    }
    .onChange(of: post.id) { _, _ in
      selectedMediaIndex = 0
    }
  }

  private func visibleRatio(in proxy: GeometryProxy) -> CGFloat {
    let frame = proxy.frame(in: .global)
    let screen = UIScreen.main.bounds
    let visibleHeight = min(frame.maxY, screen.maxY) - max(frame.minY, screen.minY)
    return max(0, min(1, visibleHeight / max(frame.height, 1)))
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

struct CaptroFeedPostVisibility: Equatable {
  let id: String
  let visibleRatio: CGFloat
  let hasVideo: Bool
}

struct CaptroFeedPostVisibilityPreferenceKey: PreferenceKey {
  static var defaultValue: [CaptroFeedPostVisibility] = []

  static func reduce(value: inout [CaptroFeedPostVisibility], nextValue: () -> [CaptroFeedPostVisibility]) {
    value.append(contentsOf: nextValue())
  }
}
