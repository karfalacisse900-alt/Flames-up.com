import SwiftUI

/// The media/player remains mounted behind this sheet. Only verified linked-record
/// fields are shown; an attachment ID is never treated as a post ID.
struct CaptroCaptureDetailsSheet: View {
  let api: MIRAAPIClient
  let story: MIRAStatusPreview?
  let stamp: String
  let onOpenPost: (String) -> Void
  @State private var post: MIRAPost?
  @State private var commerce: CaptroCommerceDetails?
  @State private var loading = false
  @State private var error: String?

  private var postID: String? {
    guard let linked = story?.linkedItem else { return nil }
    if let id = linked.postId, !id.isEmpty { return id }
    return ["post", "moment", "place"].contains(linked.type.lowercased()) ? linked.id : nil
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(stamp).font(.system(size: 11, weight: .semibold)).tracking(1.6)
          .foregroundStyle(CaptroDetailStyle.accent)
        if let title = commerce?.title ?? story?.linkedItem?.title {
          Text(title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
        }
        if let location = commerce?.displayLocation ?? story?.locationName, !location.isEmpty {
          Text(location).font(.subheadline).foregroundStyle(.secondary)
        }
        if let commerce {
          if let schedule = commerce.scheduleLabel { Text(schedule).font(.headline) }
          if let price = commerce.resolvedLowestPrice {
            Text(price.unitAmount == 0 ? "Free" : price.money).font(.headline)
          }
          if commerce.status != "active" {
            Text(commerce.status.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(.subheadline.weight(.semibold))
          }
          if let availability = commerce.compactAvailabilityLabel { Text(availability).font(.subheadline) }
          if !commerce.description.isEmpty { Text(commerce.description).font(.body) }
        }
        if let caption = story?.content, !caption.isEmpty {
          Text(caption).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        if loading { ProgressView().accessibilityLabel("Loading current details") }
        if let error {
          Text(error).font(.footnote).foregroundStyle(.secondary)
          Button("Try again") { Task { await load() } }
        }
        if let postID, post != nil {
          Button { onOpenPost(postID) } label: {
            HStack {
              Text(stamp == "MOMENT" ? "View post" : "View " + stamp.lowercased())
              Spacer()
              Image(systemName: "arrow.right")
            }
            .font(.headline).padding(.vertical, 16)
          }
          .buttonStyle(.plain)
          .accessibilityHint("Opens full details. Does not join, claim, or pay.")
        } else if story?.linkedItem != nil, !loading, error == nil {
          Text("This linked item is unavailable.").font(.footnote).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(24).padding(.top, 12)
    }
    .background(MIRATheme.Color.appBackground)
    .task(id: story?.id) { await load() }
  }

  @MainActor private func load() async {
    guard !loading, let postID else { return }
    loading = true
    error = nil
    defer { loading = false }
    // Keep cached content responsive, but validate access before offering navigation.
    let cached = await MIRAAppCacheStore.shared.loadCachedPost(id: postID)
    commerce = cached?.detail?.commerce
    do {
      let loaded: MIRAPost = try await api.get("/posts/\(postID)")
      guard !Task.isCancelled else { return }
      post = loaded
      commerce = loaded.detail?.commerce
      if loaded.captroStampKind.commerceContentType != nil {
        commerce = try await api.loadCommerce(postId: postID).commerce
      }
    } catch {
      guard !Task.isCancelled else { return }
      self.error = "Couldn't refresh this item's details. Please try again."
    }
  }
}
