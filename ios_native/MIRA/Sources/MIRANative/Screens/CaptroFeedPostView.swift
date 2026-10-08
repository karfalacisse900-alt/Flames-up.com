import Foundation
import SwiftUI
import UIKit

struct CaptroFeedPostView: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  var isPostActive = true
  let showsFeedControls: Bool
  let onFollow: () async -> Bool
  let onOpenOptions: () -> Void
  let onCreate: () -> Void
  let onOpenPost: () -> Void
  let onSave: () -> Void
  let canFollowAuthor: Bool
  let feedWidth: CGFloat
  var visibleFeedHeight: CGFloat = 0
  @Binding var stampReading: CaptroFeedStampReadingState
  @State private var selectedMediaIndex = 0
  var canRespond = true

  @Environment(\.displayScale) private var displayScale

  var body: some View {
    postContent
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onChange(of: post.id) { _, _ in
      selectedMediaIndex = 0
    }
  }

  private var postContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !post.feedMediaURLs.isEmpty {
        mediaPager
        if post.isCoverPost { coverAttribution }
      } else {
        textOnlyStamp(maxBodyLines: 16)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: max(0, feedWidth - 32), alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }


    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func textOnlyStamp(maxBodyLines: Int) -> some View {
    CaptroTextOnlyStampCard(post: post, api: api, canRespond: canRespond,
      maxBodyLines: maxBodyLines, isActive: isPostActive, onOpen: onOpenPost)
  }

  @ViewBuilder
  private var mediaPager: some View {
    let pager = CaptroMediaPager(
      post: post,
      api: api,
      isVideoActive: isVideoActive,
      isAudioActive: isPostActive,
      selectedMediaIndex: $selectedMediaIndex,
      onOpenPost: onOpenPost,
      onSave: onSave,
      showsCoverMediaOnly: false,
      frameSize: mediaSize,
      stampReading: $stampReading
    )

    pager.frame(width: mediaSize.width)
  }

  private var mediaSize: CGSize {
    // The model resolves orientation and the existing supported media policy.
    // One cover ratio sizes every carousel slide before any image downloads.
    let ratio = MIRAMediaSizing.mainFeedDisplayRatio(
      for: post.feedMediaURLs, aspectRatios: post.mediaHeightToWidthRatios)
    // An explicitly chosen Cover crop is stable, including text geometry. For
    // ordinary tall imports choose a supported responsive crop, never a spacer.
    let resolved = post.isCoverPost ? 1 / (post.mediaWriting(at: 0)?.homeAspectRatio ?? 1)
      : MIRAMediaSizing.homeDisplayRatio(ratio, width: feedWidth, visibleHeight: visibleFeedHeight)
    return CGSize(width: feedWidth, height: feedWidth * resolved)
  }

  private var coverAttribution: some View {
    let content = post.captroMediaFeedCardContent
    return VStack(alignment: .leading, spacing: 8) {
      if post.detail?.commerce != nil {
        if !content.title.isEmpty { Text(content.title).font(.subheadline.weight(.semibold)).lineLimit(2) }
        if !content.homeStampMetadata.isEmpty { Text(content.homeStampMetadata).font(.caption).foregroundStyle(.secondary) }
      }
      if let caption = post.caption ?? post.content, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(caption).font(.subheadline).lineLimit(6).fixedSize(horizontal: false, vertical: true)
      }
      Button(action: onOpenPost) {
        HStack(spacing: 7) {
          RemoteAvatar(url: post.userProfileImage, size: 24)
          Text(content.username ?? post.authorDisplayName).font(.caption.weight(.semibold))
          Spacer(minLength: 0)
        }.frame(minHeight: 36).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityHint("Opens post details")
      if post.detail?.voice != nil || post.hasAudio { CaptroStampAudio(post: post, api: api, isActive: isPostActive) }
    }.padding(.horizontal, 18).padding(.vertical, 10)
      .accessibilityIdentifier("home.cover.attribution")
  }
}

/// A first-class image-free Stamp. No fake media, fixed caption box or shared
/// tap gesture around the response controls. Header/creator open real details.
private struct CaptroTextOnlyStampCard: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let canRespond: Bool
  let maxBodyLines: Int
  let isActive: Bool
  let onOpen: () -> Void
  @ScaledMetric(relativeTo: .title) private var titleSize = 28.0
  @ScaledMetric(relativeTo: .body) private var bodySize = 16.0

  var body: some View {
    let content = post.captroMediaFeedCardContent
    VStack(alignment: .leading, spacing: 0) {
      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: 0) {
          if !content.title.isEmpty { Text(content.title)
            .font(.system(size: titleSize, weight: .bold))
            .tracking(-0.5)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
          }
          if !content.homeStampMetadata.isEmpty {
            Text(content.homeStampMetadata).font(.caption).foregroundStyle(MIRATheme.Color.textSecondary)
              .padding(.top, content.title.isEmpty ? 0 : 6)
          }
          if let caption = content.description ?? content.summaryText, !caption.isEmpty {
            Text(caption).font(.system(size: bodySize)).lineSpacing(2)
              .lineLimit(maxBodyLines).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
              .padding(.top, content.title.isEmpty && content.homeStampMetadata.isEmpty ? 0 : 12)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens full post")

      if post.response != nil {
        CaptroPostResponseView(post: post, api: api, canRespond: canRespond,
          outlinedStamp: true, onReply: onOpen)
          .padding(.top, 20)
      }

      if post.detail?.voice != nil || post.hasAudio {
        CaptroStampAudio(post: post, api: api, isActive: isActive).padding(.top, 14)
      }

      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
        .padding(.top, 20)
        .padding(.bottom, 14)
      Button(action: onOpen) {
        HStack(spacing: 10) {
          RemoteAvatar(url: post.userProfileImage, size: 32)
          Text(content.username ?? post.authorDisplayName)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
          Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .padding(20)
    .background(MIRATheme.Color.surface)
    .overlay(Rectangle().strokeBorder(MIRATheme.Color.textPrimary, lineWidth: 0.8))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("captro.textOnlyStamp")
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
