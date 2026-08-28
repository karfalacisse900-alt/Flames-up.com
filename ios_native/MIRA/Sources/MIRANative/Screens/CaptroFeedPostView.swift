import Foundation
import SwiftUI

struct CaptroFeedPostView: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  let showsFeedControls: Bool
  let onLike: () -> Void
  let onFollow: () async -> Bool
  let onOpenOptions: () -> Void
  let onCreate: () -> Void
  let onOpenPost: () -> Void
  let canFollowAuthor: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.displayScale) private var displayScale
  @State private var selectedMediaIndex = 0
  @State private var isShowingCaption = false

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
        .padding(.horizontal, 16)
      }

      CaptroLikeRow(
        isLiked: post.viewerLiked,
        likeCount: post.likesCount ?? 0,
        showsMore: captionNeedsExpansion,
        isExpanded: isShowingCaption,
        onLike: onLike,
        onToggleCaption: toggleCaption
      )

      if hasCaption {
        CaptroExpandableCaption(
          title: captionTitle,
          caption: captionText,
          isExpanded: isShowingCaption
        )
        .transition(.opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
      }

      if let locationText = post.captroFeedLocationText {
        CaptroLocationRow(location: locationText)
      }

      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 1 / max(displayScale, 1))
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(MIRATheme.Color.surface)
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
      isShowingCaption = false
    }
    .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: isShowingCaption)
  }

  private var captionTitle: String? {
    post.captroIsGuidePost ? nil : post.captroCleanTitle
  }

  private var captionText: String? {
    post.captroFeedCaptionText
  }

  private var hasCaption: Bool {
    captionTitle != nil || captionText != nil
  }

  private var captionNeedsExpansion: Bool {
    if let captionTitle, captionTitle.count > 58 { return true }
    guard let captionText else { return false }
    return captionText.count > 118 || captionText.contains("\n")
  }

  private func toggleCaption() {
    guard captionNeedsExpansion else { return }
    CaptroHaptics.light()
    withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
      isShowingCaption.toggle()
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
        .font(.body.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)

      if let location = post.captroFeedHeaderLocation {
        Text(location)
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
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

private struct CaptroLikeRow: View {
  let isLiked: Bool
  let likeCount: Int
  let showsMore: Bool
  let isExpanded: Bool
  let onLike: () -> Void
  let onToggleCaption: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button {
        CaptroHaptics.light()
        onLike()
      } label: {
        HStack(spacing: 7) {
          Image(systemName: isLiked ? "heart.fill" : "heart")
            .font(.system(size: 23, weight: .regular))
          Text(captroCompactCount(likeCount))
            .font(.callout)
            .monospacedDigit()
        }
        .foregroundStyle(isLiked ? MIRATheme.Color.like : MIRATheme.Color.textPrimary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)
      .accessibilityLabel(isLiked ? "Unlike post" : "Like post")
      .accessibilityValue("\(likeCount) likes")

      Spacer(minLength: 12)

      if showsMore {
        Button(action: onToggleCaption) {
          Text(isExpanded ? "Less" : "More")
            .font(.callout.weight(.semibold))
            .foregroundStyle(MIRATheme.Color.forest)
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show less caption" : "Show full caption")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
  }
}

private struct CaptroExpandableCaption: View {
  let title: String?
  let caption: String?
  let isExpanded: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let title {
        Text(title)
          .font(.headline)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(isExpanded ? nil : 2)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let caption {
        Text(caption)
          .font(.body)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(isExpanded ? nil : 3)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 1)
    .accessibilityElement(children: .combine)
  }
}

private struct CaptroLocationRow: View {
  let location: String

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "mappin.and.ellipse")
        .font(.subheadline.weight(.semibold))
      Text(location)
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .foregroundStyle(MIRATheme.Color.forest)
    .frame(minHeight: 44)
    .padding(.horizontal, 16)
    .padding(.top, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Location: \(location)")
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

private func captroCompactCount(_ value: Int) -> String {
  if value >= 1_000_000 { return captroCompactDecimal(Double(value) / 1_000_000, suffix: "M") }
  if value >= 1_000 { return captroCompactDecimal(Double(value) / 1_000, suffix: "K") }
  return "\(value)"
}

private func captroCompactDecimal(_ value: Double, suffix: String) -> String {
  let rounded = value >= 100 ? floor(value) : floor(value * 10) / 10
  if rounded.truncatingRemainder(dividingBy: 1) == 0 {
    return "\(Int(rounded))\(suffix)"
  }
  return String(format: "%.1f%@", rounded, suffix)
}
