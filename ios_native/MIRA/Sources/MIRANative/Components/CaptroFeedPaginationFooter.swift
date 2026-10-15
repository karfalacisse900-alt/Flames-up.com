import SwiftUI

/// One stable terminal row. Loading/error/exhaustion change its content, never
/// remove the bottom extent while a native drag/deceleration is in progress.
struct CaptroFeedPaginationFooter: View {
  let canLoadMore: Bool
  let isLoading: Bool
  let error: String?
  let needsRefresh: Bool
  let retry: () -> Void

  private func retryRow(measurement: Bool = false) -> some View {
    HStack(spacing: 12) {
      Text(measurement ? "Couldn't load more posts. Check your connection and try again." : error ?? "Couldn't load more posts. Check your connection and try again.")
        .font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button(measurement || needsRefresh ? "Refresh feed" : "Try again", action: retry)
        .frame(minHeight: 44).accessibilityIdentifier("home.pagination.retry")
    }
  }

  var body: some View {
    ZStack {
      // Measure the largest supported state at the actual width and Dynamic
      // Type size. It is neither tappable nor exposed to accessibility.
      retryRow(measurement: true).hidden().allowsHitTesting(false).accessibilityHidden(true)
      if !canLoadMore {
        Text("You're all caught up").font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary)
      } else if isLoading {
        ProgressView("Loading more posts")
      } else if error != nil {
        retryRow()
      } else {
        Button("Load more posts", action: retry).frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 60)
    .padding(.horizontal, 20)
    .accessibilityIdentifier("home.pagination")
  }
}
