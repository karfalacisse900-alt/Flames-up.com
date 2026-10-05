import Foundation
import SwiftUI
import UIKit

struct CaptroFeedPostView: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  let showsFeedControls: Bool
  let onFollow: () async -> Bool
  let onOpenOptions: () -> Void
  let onCreate: () -> Void
  let onOpenPost: () -> Void
  let onSave: () -> Void
  let canFollowAuthor: Bool
  let pageSize: CGSize?
  @Binding var selectedMediaIndex: Int
  let showsCoverMediaOnly: Bool
  var canRespond = true

  @Environment(\.displayScale) private var displayScale
  @State private var transcriptVoiceId: String?

  var body: some View {
    Group {
      if let pageSize {
        postContent
          .frame(width: pageSize.width, height: pageSize.height,
            alignment: post.feedMediaURLs.isEmpty ? .center : .topLeading)
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
        ViewThatFits(in: .vertical) {
          textOnlyStamp(maxBodyLines: 5).fixedSize(horizontal: false, vertical: true)
          textOnlyStamp(maxBodyLines: 3).fixedSize(horizontal: false, vertical: true)
          textOnlyStamp(maxBodyLines: 1).fixedSize(horizontal: false, vertical: true)
          // Accessibility text / four long choices must remain reachable, not clipped.
          ScrollView(.vertical) { textOnlyStamp(maxBodyLines: 3) }
        }
        .frame(maxHeight: pageSize.map { max(0, $0.height - 24) })
        .frame(width: max(0, (pageSize?.width ?? UIScreen.main.bounds.width) - 32), alignment: .leading)
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

      if !post.feedMediaURLs.isEmpty {
        Rectangle()
          .fill(MIRATheme.Color.hairline)
          .frame(height: 1 / max(displayScale, 1))
          .padding(.horizontal, 16)
          .padding(.top, 24)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .sheet(isPresented: Binding(get: { transcriptVoiceId != nil }, set: { if !$0 { transcriptVoiceId = nil } })) {
      if let transcriptVoiceId { CaptroVoiceTranscriptSheet(voiceId: transcriptVoiceId) }
    }
  }

  private func textOnlyStamp(maxBodyLines: Int) -> some View {
    CaptroTextOnlyStampCard(post: post, api: api, canRespond: canRespond,
      maxBodyLines: maxBodyLines, isActive: isVideoActive, onOpen: onOpenPost)
  }

  @ViewBuilder
  private var mediaPager: some View {
    let pager = CaptroMediaPager(
      post: post,
      api: api,
      isVideoActive: isVideoActive,
      selectedMediaIndex: $selectedMediaIndex,
      onOpenPost: onOpenPost,
      onSave: onSave,
      showsCoverMediaOnly: showsCoverMediaOnly,
      frameSize: pageMediaSize
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
    // Reserve the compact player and transcript action before sizing media.
    let fixedVerticalContent: CGFloat = 25 + (showsMoreButton ? 44 : 0)
    let availableMediaHeight = max(0, pageSize.height - fixedVerticalContent)
    // A short page may crop the photo vertically, but must never narrow the post.
    return CGSize(width: pageSize.width, height: min(availableMediaHeight, pageSize.width * ratio))
  }

  private var showsMoreButton: Bool {
    // Caption overflow is measured by the card's native text layout.
    return post.containsVideoMedia
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
    let content = post.captroTextOnlyCardContent
    VStack(alignment: .leading, spacing: 0) {
      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: 0) {
          Text(content.type.rawValue.uppercased())
            .font(.system(size: 12, weight: .medium))
            .tracking(2)
            .foregroundStyle(MIRATheme.Color.textMuted)
            .padding(.bottom, 16)
          Text(content.title)
            .font(.system(size: titleSize, weight: .bold))
            .tracking(-0.5)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
          if let location = content.subtitle, !location.isEmpty {
            Text(location).font(.subheadline).foregroundStyle(MIRATheme.Color.textSecondary)
              .padding(.top, 6)
          }
          if let caption = content.description ?? content.summaryText, !caption.isEmpty {
            CaptroMeasuredCaption(text: caption, size: bodySize, maxLines: maxBodyLines)
              .padding(.top, 12)
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
