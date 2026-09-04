import SwiftUI

enum CaptroDetailStyle {
  static let ink = Color.black
  static let secondary = Color.black.opacity(0.56)
  static let accent = MIRATheme.Color.like
  static let divider = Color.black.opacity(0.10)
}

struct CaptroPostDetailSections: View {
  @ObservedObject var model: PostDetailModel
  let onOpenOptions: () -> Void
  let onEditEvent: () -> Void

  private var post: MIRAPost { model.post }

  var body: some View {
    Group {
      if model.commerce != nil || post.detail?.commerce != nil {
        CaptroCommerceDetailSection(model: model)
      } else {
        switch post.detailKind {
        case .placeReview: placeReview
        case .regular: regularPost
        case .event: eventPost
        case .collection: collectionPost
        case .travel:
          CaptroTravelDetailSection(post: post, ticket: model.privateObject?.ticket, api: model.api)
        case .receipt, .invoice:
          if let document = model.privateObject?.document {
            CaptroDocumentFacts(review: document).padding(16)
          } else if !model.isLoadingObject && model.objectError == nil {
            VStack(alignment: .leading, spacing: 12) {
              Text(post.detail?.document?.merchantName ?? post.titleText).font(.system(size: 24, weight: .bold))
              Label("Document details are private", systemImage: "lock").font(.system(size: 14))
            }.padding(16)
          }
        }
      }
    }
    .foregroundStyle(CaptroDetailStyle.ink)
  }

  private var placeReview: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text((post.placeDisplayName ?? post.captroCleanTitle ?? "Place").uppercased())
        .font(.system(size: 24, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      if let district = post.displayLocationText ?? post.placeCity {
        Text(district.uppercased())
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(CaptroDetailStyle.accent)
      }

      if post.savesCount != nil || post.detail?.visitedCount != nil {
        detailDivider
        HStack(spacing: 16) {
          if let saves = post.savesCount {
            Label("\(max(0, saves)) SAVES", systemImage: "bookmark")
          }
          if let visits = post.detail?.visitedCount {
            Label("\(max(0, visits)) VISITED", systemImage: "mappin.circle")
          }
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        detailDivider
      }

      fullDescription

      CaptroDetailCreatorRow(
        post: post,
        api: model.api,
        context: post.detail?.creatorVisited == true ? "visited" : nil
      )
    }
    .padding(20)
    .background(Color.white)
    .overlay(Rectangle().stroke(CaptroDetailStyle.divider, lineWidth: 1))
    .padding(.horizontal, 16)
    .padding(.top, post.feedMediaURLs.isEmpty ? 16 : -12)
    .padding(.bottom, 8)
  }

  private var regularPost: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        CaptroDetailCreatorRow(post: post, api: model.api)
        Spacer(minLength: 0)
        Button(action: onOpenOptions) {
          Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post options")
      }
      if let title = post.captroCleanTitle, title != post.detailCaption {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .fixedSize(horizontal: false, vertical: true)
      }
      fullDescription
    }
    .padding(16)
  }

  private var eventPost: some View {
    VStack(alignment: .leading, spacing: 20) {
      CaptroEventTicketSection(post: post, ticket: model.privateObject?.ticket, api: model.api)
      if model.canEditEvent {
        Button(action: onEditEvent) {
          Label("Edit event", systemImage: "square.and.pencil")
            .font(.system(size: 14, weight: .semibold))
            .frame(minHeight: 44)
        }.buttonStyle(.plain)
      }
      CaptroDetailCreatorRow(post: post, api: model.api, context: "Hosted by", showsTime: false)
      fullDescription

      if let event = post.detail?.event,
         event.attendeesCount != nil || !(event.attendees ?? []).isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("People going").font(.system(size: 14, weight: .semibold))
          CaptroEventAttendees(event: event, api: model.api)
        }
      }

      Button {
        Task { await model.toggleAttendance() }
      } label: {
        HStack(spacing: 8) {
          if model.isUpdatingAttendance {
            ProgressView().tint(.white)
          } else if post.detail?.event?.viewerGoing == true {
            Image(systemName: "checkmark")
          }
          Text(attendanceTitle)
            .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .foregroundStyle(attendanceEnabled ? Color.white : CaptroDetailStyle.secondary)
        .background(attendanceEnabled ? CaptroDetailStyle.accent : Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .disabled(!attendanceEnabled || model.isUpdatingAttendance)
      .accessibilityLabel(attendanceTitle)
    }
    .padding(16)
  }

  private var attendanceEnabled: Bool { post.detail?.event?.attendanceEnabled == true }
  private var attendanceTitle: String {
    guard attendanceEnabled else { return "RSVP unavailable" }
    return post.detail?.event?.viewerGoing == true ? "GOING" : "I'M GOING"
  }

  private var collectionPost: some View {
    VStack(alignment: .leading, spacing: 16) {
      if post.detail?.collection?.items != nil {
        let items = post.detailCollectionItems
        Text("\(items.count) \(items.allSatisfy { $0.detailKind == .placeReview } ? "PLACES" : "POSTS")")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CaptroDetailStyle.accent)
      }
      Text(post.captroCleanTitle ?? "Collection")
        .font(.system(size: 24, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      CaptroDetailCreatorRow(post: post, api: model.api, context: "by", showsTime: false)
      fullDescription

      HStack(spacing: 10) {
        Button {
          Task { await model.toggleSave() }
        } label: {
          Label(post.viewerSaved ? "Saved Collection" : "Save Collection", systemImage: post.viewerSaved ? "bookmark.fill" : "bookmark")
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.white)
            .background(CaptroDetailStyle.accent)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .disabled(model.isSaving)
        ShareLink(item: captroDetailShareURL(post)) {
          Label("Share", systemImage: "square.and.arrow.up")
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CaptroDetailStyle.divider, lineWidth: 1))
        }
      }
      .buttonStyle(.plain)

      if !post.detailCollectionItems.isEmpty {
        let items = post.detailCollectionItems
        VStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            CaptroCollectionPostRow(index: index + 1, post: item, api: model.api)
            if index < items.count - 1 { detailDivider }
          }
        }
      } else {
        Text("No places or posts in this collection yet.")
          .font(.system(size: 14))
          .foregroundStyle(CaptroDetailStyle.secondary)
          .padding(.vertical, 12)
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private var fullDescription: some View {
    if !post.detailCaption.isEmpty {
      Text(post.detailCaption)
        .font(.system(size: 15))
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
  }

  private var detailDivider: some View {
    Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
  }
}

struct CaptroDetailCreatorRow: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  var context: String? = nil
  var showsTime = true

  var body: some View {
    Group {
      if let userId = post.userId, !userId.isEmpty {
        NavigationLink(destination: UserProfileNativeView(userId: userId, api: api).miraHideTabBarOnAppear()) {
          label
        }
        .buttonStyle(.plain)
      } else {
        label
      }
    }
    .accessibilityLabel("View \(post.detailCreatorHandle)'s profile")
  }

  private var label: some View {
    HStack(spacing: 9) {
      RemoteAvatar(url: post.userProfileImage, size: 34)
      VStack(alignment: .leading, spacing: 4) {
        Text(showsTime ? post.detailCreatorHandle : [context, post.detailCreatorHandle].compactMap { $0 }.joined(separator: " "))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(CaptroDetailStyle.ink)
          .lineLimit(2)
        if showsTime {
          Text([context, relativeAge(post.createdAt)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 11))
            .foregroundStyle(CaptroDetailStyle.secondary)
        }
      }
    }
    .frame(minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
  }
}

struct CaptroDetailLocationSection: View {
  let post: MIRAPost
  var showsDivider = true

  var body: some View {
    if let url = post.detailMapURL,
       post.placeDisplayName != nil || post.detail?.event?.venueName != nil {
      VStack(alignment: .leading, spacing: 12) {
        if showsDivider {
          Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
        }
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "mappin.and.ellipse")
            .font(.system(size: 18))
            .padding(.top, 2)
          VStack(alignment: .leading, spacing: 5) {
            Text(post.detail?.event?.venueName ?? post.placeDisplayName ?? "")
              .font(.system(size: 14, weight: .semibold))
            if let address = post.detail?.event?.address ?? post.placeDisplaySubtitle {
              Text(address)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            }
            Link(destination: url) {
              Label("View location", systemImage: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CaptroDetailStyle.accent)
                .frame(minHeight: 36, alignment: .leading)
            }
          }
          Spacer(minLength: 0)
        }
        .foregroundStyle(CaptroDetailStyle.ink)
      }
    }
  }
}

struct CaptroEventAttendees: View {
  let event: CaptroEventDetails
  let api: MIRAAPIClient

  private var people: [MIRATaggedUserPayload] {
    var seen = Set<String>()
    return Array((event.attendees ?? []).filter { seen.insert($0.id).inserted }.prefix(5))
  }
  private var remainder: Int { max(0, (event.attendeesCount ?? people.count) - people.count) }

  var body: some View {
    HStack(spacing: -7) {
      ForEach(people) { person in
        NavigationLink(destination: UserProfileNativeView(userId: person.id, api: api).miraHideTabBarOnAppear()) {
          RemoteAvatar(url: person.profileImage, size: 36)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.username ?? person.fullName ?? "Attendee")
      }
      if remainder > 0 {
        Text("+\(remainder)")
          .font(.system(size: 12, weight: .semibold))
          .padding(.horizontal, 10)
          .frame(height: 36)
          .background(Color.black.opacity(0.05))
          .clipShape(Capsule())
      } else if people.isEmpty {
        Text("\(max(0, event.attendeesCount ?? 0)) going")
          .font(.system(size: 13))
          .foregroundStyle(CaptroDetailStyle.secondary)
      }
    }
  }
}

private struct CaptroCollectionPostRow: View {
  let index: Int
  @StateObject private var model: PostDetailModel

  init(index: Int, post: MIRAPost, api: MIRAAPIClient) {
    self.index = index
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
  }

  var body: some View {
    HStack(spacing: 8) {
      Text("\(index)")
        .font(.system(size: 13, weight: .semibold))
        .frame(minWidth: 18)
      NavigationLink(destination: PostDetailNativeView(post: model.post, api: model.api)) {
        HStack(spacing: 10) {
          if let url = model.post.thumbnailMediaURLs.first {
            RemoteMediaView(url: url, isVideo: false, contentMode: .fill, maxPixelSize: 240)
              .frame(width: 52, height: 52)
              .clipped()
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(model.post.placeDisplayName ?? model.post.titleText)
              .font(.system(size: 13, weight: .semibold))
              .lineLimit(2)
            if let location = model.post.placeCity ?? model.post.displayLocationText {
              Text(location)
                .font(.system(size: 11))
                .foregroundStyle(CaptroDetailStyle.secondary)
                .lineLimit(2)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Button {
        Task { await model.toggleSave() }
      } label: {
        Image(systemName: model.post.viewerSaved ? "bookmark.fill" : "bookmark")
          .font(.system(size: 18))
          .foregroundStyle(CaptroDetailStyle.accent)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .disabled(model.isSaving)
      .accessibilityLabel(model.post.viewerSaved ? "Unsave \(model.post.titleText)" : "Save \(model.post.titleText)")
    }
    .foregroundStyle(CaptroDetailStyle.ink)
    .padding(.vertical, 10)
    .alert("Couldn't update saved posts", isPresented: Binding(
      get: { model.actionError != nil },
      set: { if !$0 { model.actionError = nil } }
    )) {
      Button("OK", role: .cancel) { model.actionError = nil }
    } message: {
      Text(model.actionError ?? "")
    }
    .task { await model.hydrateFromLocalCache() }
    .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
      guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
      model.applyEngagementUpdate(update)
    }
  }
}

func captroDetailShareURL(_ post: MIRAPost) -> URL {
  MIRAProductionBackend.siteURL("post/\(post.id)")
}
