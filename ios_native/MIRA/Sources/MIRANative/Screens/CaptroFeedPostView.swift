import Foundation
import SwiftUI
import UIKit

/// Retained by the feed, but observed only by the affected row. Swiping one
/// carousel or measuring one stamp must not invalidate the whole lazy stack.
@MainActor
final class CaptroFeedRowState: ObservableObject {
  @Published private(set) var selectedMediaID: String?
  @Published var stampReading = CaptroFeedStampReadingState()

  func select(_ mediaID: String?) {
    guard selectedMediaID != mediaID else { return }
    selectedMediaID = mediaID
  }
}

@MainActor
final class CaptroFeedRowStateStore: ObservableObject {
  // Intentionally not @Published. The store retains row state through lazy
  // unmount/remount and navigation without broadcasting child mutations.
  private var rows: [String: CaptroFeedRowState] = [:]

  func state(for postID: String) -> CaptroFeedRowState {
    if let existing = rows[postID] { return existing }
    let state = CaptroFeedRowState()
    rows[postID] = state
    return state
  }
}

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
  var frameRatio: CGFloat? = nil
  @ObservedObject var rowState: CaptroFeedRowState
  var onMediaSelectionChange: (String) -> Void = { _ in }
  private var selectedMediaIndex: Binding<Int> {
    Binding(get: { post.feedMediaIdentities.firstIndex(of: rowState.selectedMediaID ?? "") ?? 0 }, set: { index in
      let identities = post.feedMediaIdentities
      guard identities.indices.contains(index), rowState.selectedMediaID != identities[index] else { return }
      rowState.select(identities[index])
      onMediaSelectionChange(identities[index])
      CaptroFeedDiagnostics.event("slide", feed: "home", reason: "carousel_selection", post: post.id, media: identities[index])
    })
  }
  var canRespond = true

  @Environment(\.displayScale) private var displayScale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
#if CAPTRO_PERFORMANCE_REVIEW
    let work = CaptroScrollWorkMetrics.begin()
    defer { CaptroScrollWorkMetrics.end("rowBody", start: work) }
#endif
    return postContent
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var postContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !post.feedMediaURLs.isEmpty {
        mediaPager
      } else if !post.isLegacyOrdinaryTextPost {
        structuredStamp(maxBodyLines: 3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: max(0, feedWidth - 32), alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }


    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func structuredStamp(maxBodyLines: Int) -> some View {
    CaptroStructuredFeedCard(post: post, api: api,
      maxBodyLines: maxBodyLines, isActive: isPostActive, onOpen: onOpenPost)
  }

  @ViewBuilder
  private var mediaPager: some View {
    let pager = CaptroMediaPager(
      post: post,
      api: api,
      isVideoActive: isVideoActive,
      isAudioActive: isPostActive,
      selectedMediaIndex: selectedMediaIndex,
      onOpenPost: onOpenPost,
      onSave: onSave,
      showsCoverMediaOnly: false,
      frameSize: mediaSize,
      stampReading: $rowState.stampReading
    )

    pager.frame(width: mediaSize.width)
  }

  private var mediaSize: CGSize {
    // The first item establishes the feed frame for the whole post. Individual
    // slides retain their own source geometry and crop inside this frame.
    CGSize(width: feedWidth, height: feedWidth * (frameRatio ?? post.feedFrameHeightToWidthRatio))
  }

}

/// Image-free structured objects retain their real Details/action destination.
/// Ordinary legacy text posts are not rendered by the Home card component.
private struct CaptroStructuredFeedCard: View {
  let post: MIRAPost
  let api: MIRAAPIClient
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

      if post.hasAudio {
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
    .accessibilityIdentifier("captro.structuredStamp")
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
