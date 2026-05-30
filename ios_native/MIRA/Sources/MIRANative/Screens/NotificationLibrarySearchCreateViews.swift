import AVFoundation
import CoreLocation
import MapKit
import PhotosUI
import SwiftUI

@MainActor
final class NotificationNativeModel: ObservableObject {
  @Published var notifications: [MIRANotification] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    isLoading = notifications.isEmpty
    defer { isLoading = false }
    do {
      notifications = try await api.get("/notifications?limit=60")
      let _: EmptyResponse = try await api.post("/notifications/mark-read", body: EmptyBody())
      errorMessage = nil
    } catch {
      errorMessage = "Notifications could not load."
    }
  }
}

public struct NotificationNativeView: View {
  @StateObject private var model: NotificationNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: NotificationNativeModel(api: api))
  }

  public var body: some View {
    ScrollView {
      LazyVStack(spacing: MIRATheme.Space.sm) {
        if model.isLoading && model.notifications.isEmpty {
          ForEach(0..<6, id: \.self) { _ in notificationSkeleton }
        } else if model.notifications.isEmpty {
          MIRAEmptyState(title: "No notifications yet", message: "Likes, replies, follows, gifts, and posts will appear here.", systemImage: "bell")
        } else {
          ForEach(model.notifications) { item in
            notificationRow(item)
          }
        }
      }
      .padding(MIRATheme.Space.md)
    }
    .background(MIRATheme.Color.appBackground)
    .miraScreenEnter(.push)
    .navigationTitle("Notifications")
    .miraHideTabBarOnAppear()
    .task { await model.load() }
  }

  private func notificationRow(_ item: MIRANotification) -> some View {
    HStack(spacing: MIRATheme.Space.md) {
      Image(systemName: icon(for: item.type))
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title ?? "New activity")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(item.body ?? "Something new happened on MIRA.")
          .font(.system(size: 14, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(2)
      }
      Spacer()
      if item.isRead?.value == false {
        Circle().fill(MIRATheme.Color.accent).frame(width: 8, height: 8)
      }
    }
    .padding(MIRATheme.Space.md)
    .miraCardSurface()
  }

  private var notificationSkeleton: some View {
    HStack(spacing: MIRATheme.Space.md) {
      Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 180, height: 14)
        RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 250, height: 12)
      }
    }
    .padding(MIRATheme.Space.md)
    .miraCardSurface()
    .redacted(reason: .placeholder)
  }

  private func icon(for type: String?) -> String {
    switch type {
    case "like": return "heart.fill"
    case "comment", "comment_reply": return "bubble.left.fill"
    case "follow": return "person.badge.plus"
    case "message": return "message.fill"
    case "coin_gift": return "gift.fill"
    case "new_post": return "sparkles"
    default: return "bell.fill"
    }
  }
}

@MainActor
final class LibraryNativeModel: ObservableObject {
  enum Section: String, CaseIterable, Identifiable, Hashable {
    case inspiration = "Inspiration"
    case outfits = "Outfits"
    case places = "Places"
    case food = "Food"
    case photos = "Photos"
    case videos = "Videos"
    case liked = "Liked"

    var id: String { rawValue }

    var systemImage: String {
      switch self {
      case .inspiration: return "lightbulb"
      case .outfits: return "tshirt"
      case .places: return "mappin.and.ellipse"
      case .food: return "fork.knife"
      case .photos: return "photo.on.rectangle"
      case .videos: return "play.rectangle"
      case .liked: return "heart"
      }
    }

    var collectionName: String? {
      self == .liked ? nil : rawValue
    }
  }

  @Published var selectedSection: Section = .inspiration
  @Published var posts: [MIRAPost] = []
  @Published var collectionCounts: [String: Int] = [:]
  @Published var isLoading = false
  @Published var errorMessage: String?
  let api: MIRAAPIClient
  private var postsBySection: [Section: [MIRAPost]] = [:]

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load(force: Bool = false) async {
    await loadCollectionCounts()
    await loadSelectedSection(force: force)
  }

  func select(_ section: Section) async {
    guard selectedSection != section || posts.isEmpty else { return }
    selectedSection = section
    if let cached = postsBySection[section] {
      posts = cached
      errorMessage = nil
      return
    }
    await loadSelectedSection(force: false)
  }

  private func loadSelectedSection(force: Bool) async {
    if let cached = postsBySection[selectedSection], !force {
      posts = cached
      errorMessage = nil
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let loaded: [MIRAPost]
      if selectedSection == .liked {
        loaded = try await api.get("/library/liked")
      } else if let collectionName = selectedSection.collectionName {
        let encoded = collectionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? collectionName
        loaded = try await api.get("/library/saved?collection=\(encoded)")
      } else {
        loaded = []
      }
      posts = loaded
      postsBySection[selectedSection] = loaded
      errorMessage = nil
    } catch {
      if posts.isEmpty {
        errorMessage = "Could not load this library section."
      }
    }
  }

  private func loadCollectionCounts() async {
    guard let collections: [MIRALibraryCollection] = try? await api.get("/library/collections") else { return }
    var counts: [String: Int] = [:]
    for item in collections {
      let name = item.collection ?? item.name ?? ""
      guard !name.isEmpty else { continue }
      counts[name] = item.count ?? 0
    }
    collectionCounts = counts
  }

  func count(for section: Section) -> Int {
    guard let collectionName = section.collectionName else { return 0 }
    return collectionCounts[collectionName] ?? 0
  }
}

public struct LibraryNativeView: View {
  @StateObject private var model: LibraryNativeModel
  @Environment(\.dismiss) private var dismiss

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: LibraryNativeModel(api: api))
  }

  public var body: some View {
    VStack(spacing: 0) {
      libraryHeader

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          sectionRail

          if let errorMessage = model.errorMessage {
            libraryErrorBanner(errorMessage)
              .padding(.horizontal, MIRATheme.Space.md)
          }

          if model.isLoading && model.posts.isEmpty {
            librarySkeleton
          } else if model.posts.isEmpty {
            MIRAEmptyState(
              title: "Nothing saved here yet",
              message: emptyMessage,
              systemImage: model.selectedSection.systemImage
            )
            .padding(.horizontal, MIRATheme.Space.md)
          } else {
            postGrid(posts: model.posts)
          }
        }
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, MIRATheme.Space.xxl)
      }
    }
    .background(MIRATheme.Color.appBackground)
    .miraScreenEnter(.push)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .miraHideTabBarOnAppear()
    .task { await model.load() }
  }

  private var libraryHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Button { dismiss() } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.miraPress)

      VStack(alignment: .leading, spacing: 2) {
        Text("My Library")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text("Saved posts organized by what inspired you.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }

      Spacer()
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, MIRATheme.Space.sm)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var sectionRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MIRATheme.Space.sm) {
        ForEach(LibraryNativeModel.Section.allCases) { section in
          let isSelected = model.selectedSection == section
          Button {
            Task { await model.select(section) }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .semibold))
              Text(section.rawValue)
                .font(.system(size: 14, weight: .semibold))
              if section != .liked {
                Text("\(model.count(for: section))")
                  .font(.system(size: 11, weight: .bold))
                  .foregroundStyle(isSelected ? .white.opacity(0.78) : MIRATheme.Color.textMuted)
              }
            }
            .foregroundStyle(isSelected ? .white : MIRATheme.Color.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(isSelected ? MIRATheme.Color.forest : MIRATheme.Color.surfaceRaised)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : MIRATheme.Color.hairline, lineWidth: 1))
          }
          .buttonStyle(.miraPress)
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
  }

  private func libraryErrorBanner(_ message: String) -> some View {
    Text(message)
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(.red)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MIRATheme.Space.md)
      .background(Color.red.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func postGrid(posts: [MIRAPost]) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 2), spacing: 10) {
      ForEach(posts) { post in
        libraryPostTile(post)
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private func libraryPostTile(_ post: MIRAPost) -> some View {
    NavigationLink(destination: PostDetailNativeView(post: post, api: model.api)) {
      ZStack(alignment: .bottomLeading) {
        MIRATheme.Color.mediaPlaceholder

        if let media = post.thumbnailMediaURLs.first ?? post.feedMediaURLs.first {
          RemoteMediaView(url: media, isVideo: media.isVideoURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
          ZStack {
            MIRATheme.Color.surfaceSoft
            Text(post.titleText)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .lineLimit(4)
              .multilineTextAlignment(.leading)
              .padding(12)
          }
        }

        LinearGradient(colors: [.clear, .black.opacity(0.52)], startPoint: .center, endPoint: .bottom)
          .allowsHitTesting(false)

        Text(post.titleText)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
          .padding(10)
          .shadow(radius: 4)
      }
      .aspectRatio(3.0 / 4.0, contentMode: .fit)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
      .clipped()
    }
    .buttonStyle(.plain)
  }

  private var librarySkeleton: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
      ForEach(0..<6, id: \.self) { _ in
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(MIRATheme.Color.surfaceSoft)
          .aspectRatio(3.0 / 4.0, contentMode: .fit)
          .redacted(reason: .placeholder)
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private var emptyMessage: String {
    if model.selectedSection == .liked {
      return "Posts you like will show here."
    }
    return "Tap save on a post and choose \(model.selectedSection.rawValue) to organize it here."
  }
}

@MainActor
final class SearchUsersNativeModel: ObservableObject {
  @Published var query = ""
  @Published var users: [MIRAUser] = []
  @Published var isLoading = false
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func search() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else {
      users = []
      return
    }
    isLoading = true
    defer { isLoading = false }
    users = (try? await api.get("/users/search/\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed)")) ?? []
  }
}

public struct SearchUsersNativeView: View {
  @StateObject private var model: SearchUsersNativeModel
  @Environment(\.dismiss) private var dismiss

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: SearchUsersNativeModel(api: api))
  }

  public var body: some View {
    VStack(spacing: 0) {
      searchHeader

      List {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
          Text("Search people by name or username.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .listRowBackground(MIRATheme.Color.appBackground)
        } else if model.isLoading && model.users.isEmpty {
          HStack {
            ProgressView()
            Text("Searching...")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
          .listRowBackground(MIRATheme.Color.appBackground)
        } else if model.users.isEmpty {
          Text("No people found.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .listRowBackground(MIRATheme.Color.appBackground)
        } else {
          ForEach(model.users) { user in
            NavigationLink(destination: UserProfileNativeView(userId: user.id, api: model.api)) {
              HStack(spacing: MIRATheme.Space.md) {
                RemoteAvatar(url: user.profileImage, size: 44)
                VStack(alignment: .leading) {
                  Text(user.displayName).font(.system(size: 16, weight: .semibold))
                  if let bio = user.bio, !bio.isEmpty {
                    Text(bio).font(.system(size: 13)).foregroundStyle(MIRATheme.Color.textMuted).lineLimit(1)
                  }
                }
              }
            }
            .buttonStyle(.plain)
            .listRowBackground(MIRATheme.Color.surface)
          }
        }
      }
      .scrollContentBackground(.hidden)
    }
    .background(MIRATheme.Color.appBackground)
    .miraScreenEnter(.push)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .miraHideTabBarOnAppear()
    .task(id: model.query) {
      try? await Task.sleep(nanoseconds: 250_000_000)
      await model.search()
    }
  }

  private var searchHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Button { dismiss() } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.miraPress)

      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        TextField("Search people", text: $model.query)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(.system(size: 16, weight: .medium))
        if !model.query.isEmpty {
          Button {
            model.query = ""
            model.users = []
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 44)
      .background(MIRATheme.Color.surfaceRaised)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(MIRATheme.Color.hairline, lineWidth: 1))
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, MIRATheme.Space.sm)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }
}

private struct MIRAEditorPresentation: Identifiable {
  let id = UUID()
  let media: MIRAPickedMedia
  var replacementIndex: Int?
  var returnsToCamera = false
}

private enum PostDetailSheet: Identifiable, Equatable {
  case location
  case city
  case people
  case tags
  case music
  case aiAssist

  var id: String {
    switch self {
    case .location: return "location"
    case .city: return "city"
    case .people: return "people"
    case .tags: return "tags"
    case .music: return "music"
    case .aiAssist: return "aiAssist"
    }
  }
}

private struct MIRABroadDisplayLocation: Codable, Hashable {
  var city: String?
  var region: String?
  var country: String?
  var label: String?
  var source: String = "none"
  var visibility: String = "hidden"

  var hasVisibleLabel: Bool {
    let clean = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return visibility != "hidden" && !clean.isEmpty
  }
}

private struct MIRABroadLocationReverseResponse: Decodable {
  let location: MIRABroadLocationSearchResult?
}

private struct MIRABroadLocationSearchResponse: Decodable {
  let locations: [MIRABroadLocationSearchResult]
}

private struct MIRABroadLocationSearchResult: Decodable, Identifiable, Hashable {
  let city: String?
  let region: String?
  let country: String?
  let label: String?
  let displayLocationLabel: String?
  let displayLocationSource: String?

  var id: String {
    [resolvedLabel, city, region, country].compactMap { $0 }.joined(separator: "-")
  }

  var resolvedLabel: String {
    let explicit = (displayLocationLabel ?? label)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !explicit.isEmpty { return explicit }
    return [city, region, country]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

  var displayLocation: MIRABroadDisplayLocation {
    MIRABroadDisplayLocation(
      city: city,
      region: region,
      country: country,
      label: resolvedLabel,
      source: displayLocationSource ?? "mapbox_reverse_geocode",
      visibility: "public"
    )
  }
}

private struct MIRAExactPostPlace: Identifiable, Hashable {
  let provider: String
  let providerPlaceId: String?
  let name: String
  let formattedAddress: String?
  let latitude: Double?
  let longitude: Double?
  let category: String?
  let city: String?
  let region: String?
  let country: String?

  var id: String {
    providerPlaceId ?? [displayName, addressText].compactMap { $0 }.joined(separator: "-")
  }

  var displayName: String {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? "Place" : clean
  }

  var addressText: String? {
    for value in [formattedAddress, cityCountryText] {
      let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !clean.isEmpty { return clean }
    }
    return nil
  }

  private var cityCountryText: String? {
    let parts = [city, region, country]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  init(
    provider: String = "apple_mapkit",
    providerPlaceId: String?,
    name: String,
    formattedAddress: String?,
    latitude: Double?,
    longitude: Double?,
    category: String?,
    city: String?,
    region: String?,
    country: String?
  ) {
    self.provider = provider
    self.providerPlaceId = providerPlaceId
    self.name = name
    self.formattedAddress = formattedAddress
    self.latitude = latitude
    self.longitude = longitude
    self.category = category
    self.city = city
    self.region = region
    self.country = country
  }

  init(mapItem: MKMapItem) {
    let placemark = mapItem.placemark
    let coordinate = placemark.coordinate
    let name = (mapItem.name ?? placemark.name ?? placemark.title ?? "Place")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let addressParts = [
      [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " "),
      placemark.locality,
      placemark.administrativeArea,
      placemark.country
    ]
      .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
      .filter { !$0.isEmpty }
    let address = addressParts.joined(separator: ", ")
    let providerIdBase = [
      name,
      placemark.locality ?? "",
      String(format: "%.5f", coordinate.latitude),
      String(format: "%.5f", coordinate.longitude)
    ]
      .joined(separator: "-")
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_.-]+"#, with: "-", options: .regularExpression)
    self.init(
      providerPlaceId: "apple-mapkit-\(providerIdBase)",
      name: name.isEmpty ? "Place" : name,
      formattedAddress: address.isEmpty ? nil : address,
      latitude: CLLocationCoordinate2DIsValid(coordinate) ? coordinate.latitude : nil,
      longitude: CLLocationCoordinate2DIsValid(coordinate) ? coordinate.longitude : nil,
      category: mapItem.pointOfInterestCategory?.rawValue,
      city: placemark.locality,
      region: placemark.administrativeArea,
      country: placemark.country
    )
  }
}

@MainActor
private final class MIRABroadLocationResolver: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var isResolving = false
  private let manager = CLLocationManager()
  private var continuation: CheckedContinuation<CLLocation?, Never>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
  }

  func resolveCurrentLocation() async -> CLLocation? {
    guard !isResolving else { return nil }
    isResolving = true
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        await self?.finish(nil)
      }
      switch manager.authorizationStatus {
      case .notDetermined:
        manager.requestWhenInUseAuthorization()
      case .authorizedAlways, .authorizedWhenInUse:
        manager.requestLocation()
      case .denied, .restricted:
        finish(nil)
      @unknown default:
        finish(nil)
      }
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard continuation != nil else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finish(nil)
    case .notDetermined:
      break
    @unknown default:
      finish(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    finish(locations.last)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finish(nil)
  }

  private func finish(_ location: CLLocation?) {
    guard let continuation else { return }
    self.continuation = nil
    isResolving = false
    continuation.resume(returning: location)
  }
}

public struct CreatePostNativeView: View {
  let api: MIRAAPIClient
  private let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @StateObject private var broadLocationResolver = MIRABroadLocationResolver()
  @State private var title = ""
  @State private var bodyText = ""
  @State private var mediaItems: [MIRAPickedMedia] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var showPreview = false
  @State private var isEditingPostDetails = false
  @State private var isPosting = false
  @State private var isLoadingMedia = false
  @State private var errorMessage: String?
  @State private var editingMedia: MIRAEditorPresentation?
  @State private var editedCameraMedia: MIRAPickedMedia?
  @State private var activePostDetailSheet: PostDetailSheet?
  @State private var selectedPlace: MIRAExactPostPlace?
  @State private var broadLocation = MIRABroadDisplayLocation()
  @State private var showBroadLocation = false
  @State private var broadLocationError: String?
  @State private var hasLoadedBroadLocation = false
  @State private var taggedUsers: [MIRAUser] = []
  @State private var hashtags: [String] = []
  @State private var selectedAudioTrack: MIRAAudiusTrack?
  @State private var postAssistResponse: MIRAPostAssistResponse?
  @State private var isGeneratingPostAssist = false
  @State private var postAssistError: String?

  public init(api: MIRAAPIClient, onClose: (() -> Void)? = nil) {
    self.api = api
    self.onClose = onClose
  }

  public var body: some View {
    Group {
      if isEditingPostDetails {
        finalPostPage
      } else {
        mediaFirstPage
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .miraHideTabBarOnAppear()
    .miraScreenEnter(.modal)
    .navigationBarBackButtonHidden(true)
    .onAppear {
      MIRAPlaybackCoordinator.pauseAll(reason: "post_creation_open")
    }
    .task {
      await loadBroadLocationDefaultIfNeeded()
    }
    .onChange(of: pickerItems) { _, newItems in
      Task { await loadPickerItems(newItems) }
    }
    .onChange(of: showBroadLocation) { _, isOn in
      guard isOn else { return }
      Task { await resolveCurrentBroadLocationForPost() }
    }
    .miraBottomSheet(isPresented: $showPreview, preferredHeightFraction: 0.72) { _ in
      ComposerPreviewSheet(title: title, bodyText: bodyText, mediaItems: mediaItems)
    }
    .miraBottomSheet(isPresented: postDetailSheetPresentedBinding, preferredHeightFraction: postDetailSheetHeightFraction) { closeSheet in
      switch activePostDetailSheet {
      case .location:
        PostLocationPickerSheet(api: api, selectedPlace: $selectedPlace, onClose: closeSheet)
      case .city:
        PostBroadLocationPickerSheet(api: api, broadLocation: $broadLocation, showBroadLocation: $showBroadLocation, onClose: closeSheet)
      case .people:
        PostPeopleTagSheet(api: api, selectedUsers: $taggedUsers, onClose: closeSheet)
      case .tags:
        PostHashtagSheet(hashtags: $hashtags, onClose: closeSheet)
      case .music:
        MIRAAudiusMusicPickerSheet(api: api, selectedTrack: $selectedAudioTrack, onClose: closeSheet)
      case .aiAssist:
        PostAIAssistSheet(
          response: postAssistResponse,
          isLoading: isGeneratingPostAssist,
          errorMessage: postAssistError,
          onGenerate: {
            Task { await generatePostAssist() }
          },
          onApplyHeadline: { suggestion in
            title = suggestion
            activePostDetailSheet = nil
          },
          onApplyCaption: { suggestion in
            bodyText = suggestion
            activePostDetailSheet = nil
          },
          onClose: closeSheet
        )
      case nil:
        Color.clear
      }
    }
    .miraFullScreenOverlay(item: $editingMedia, background: .black) { item, closeEditor in
      MIRANativeMediaEditorView(media: item.media, mode: .post, onClose: closeEditor) { edited in
        if item.returnsToCamera {
          editedCameraMedia = edited
        } else if let index = item.replacementIndex, mediaItems.indices.contains(index) {
          mediaItems[index] = edited
        } else {
          mediaItems.append(edited)
          withAnimation(.snappy(duration: 0.2)) {
            isEditingPostDetails = true
          }
        }
      }
      .ignoresSafeArea()
    }
  }

  private var postDetailSheetPresentedBinding: Binding<Bool> {
    Binding(
      get: { activePostDetailSheet != nil },
      set: { isPresented in
        if !isPresented {
          activePostDetailSheet = nil
        }
      }
    )
  }

  private var postDetailSheetHeightFraction: CGFloat {
    switch activePostDetailSheet {
    case .tags: return 0.50
    case .city: return 0.62
    case .music: return 0.78
    case .aiAssist: return 0.70
    default: return 0.76
    }
  }

  private var mediaFirstPage: some View {
    ZStack {
      MIRAStoryLiveCameraView(
        editedMedia: editedCameraMedia,
        dismissesOnCapture: false,
        dismissesOnCancel: false,
        onCapture: { media in
          addCapturedMediaAndContinue(media)
        },
        onCancel: {
          close()
        },
        onMusic: {
          activePostDetailSheet = .music
        },
        onEdit: { media, _ in
          editingMedia = MIRAEditorPresentation(media: media, returnsToCamera: true)
        }
      )
      .ignoresSafeArea()

      if isLoadingMedia {
        ProgressView()
          .tint(.white)
          .scaleEffect(1.12)
      }
    }
    .background(Color.black.ignoresSafeArea())
  }

  private var finalPostPage: some View {
    GeometryReader { proxy in
      VStack(spacing: 0) {
        postDetailsTopBar

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 0) {
            postDetailsMediaStrip
              .padding(.top, 24)

            postDetailsTextFields
              .padding(.top, 34)

            Spacer(minLength: max(120, proxy.size.height * 0.22))

            Rectangle()
              .fill(MIRATheme.Color.hairline.opacity(0.75))
              .frame(height: 0.7)
              .padding(.top, 24)

            postOptionRow(
              icon: "mappin.circle",
              title: selectedPlace?.displayName ?? "Add place",
              subtitle: selectedPlace?.addressText ?? "Restaurant, gym, cafe, park, or venue",
              action: { activePostDetailSheet = .location }
            )
            broadLocationOptionRow
            postOptionRow(
              icon: "music.note",
              title: selectedAudioTrack?.displayTitle ?? "Add music",
              subtitle: selectedAudioTrack?.displayArtist ?? "Search Audius tracks",
              action: { activePostDetailSheet = .music }
            )
          }
          .padding(.horizontal, 16)
          .padding(.bottom, max(proxy.safeAreaInsets.bottom + 28, 52))
        }
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
    }
  }

  private var postDetailsTopBar: some View {
    HStack {
      Button {
        returnToCapture()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 34, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 54, height: 54)
      }
      .buttonStyle(.plain)

      Spacer()

      HStack(spacing: 10) {
        Button { showPreview = true } label: {
          HStack(spacing: 6) {
            Text("Preview")
              .font(.system(size: 17, weight: .semibold))
            Image(systemName: "eye")
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .padding(.horizontal, 15)
          .frame(height: 46)
          .background(MIRATheme.Color.surfaceSoft.opacity(0.72))
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)

        Button {
          Task { await submit() }
        } label: {
          HStack(spacing: 7) {
            if isPosting {
              ProgressView()
                .tint(.white)
                .scaleEffect(0.72)
            }
            Text(isPosting ? "Posting" : "Post")
              .font(.system(size: 17, weight: .semibold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 19)
          .frame(height: 46)
          .background(canPost && !isPosting ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.45))
          .clipShape(Capsule())
          .shadow(color: MIRATheme.Color.forest.opacity(canPost ? 0.18 : 0), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isPosting || !canPost)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .frame(height: 98)
  }

  private var postDetailsMediaStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 14) {
        ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, item in
          postDetailsMediaTile(item, index: index)
        }

        PhotosPicker(
          selection: $pickerItems,
          maxSelectionCount: 10,
          matching: .any(of: [.images, .videos]),
          preferredItemEncoding: .current
        ) {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(MIRATheme.Color.surfaceSoft.opacity(0.6))
            .frame(width: 104, height: 108)
            .overlay {
              Image(systemName: "plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.82))
            }
            .overlay(alignment: .bottom) {
              Text("Add")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MIRATheme.Color.textMuted)
                .padding(.bottom, 10)
            }
        }
      }
      .padding(.horizontal, 1)
    }
  }

  private func postDetailsMediaTile(_ media: MIRAPickedMedia, index: Int) -> some View {
    postComposerMedia(media, width: 104, height: 108, cornerRadius: 14)
      .overlay(alignment: .topTrailing) {
        if media.kind == .video {
          Image(systemName: "play.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(.black.opacity(0.58))
            .clipShape(Circle())
            .padding(8)
        }
      }
      .overlay(alignment: .bottomLeading) {
        Text(index == 0 ? "Cover" : "\(index + 1)")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .frame(height: 31)
          .background(.black.opacity(0.52))
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          .padding(8)
          .allowsHitTesting(false)
      }
      .overlay(alignment: .topLeading) {
        if mediaItems.count > 1 {
          Button {
            removeMedia(at: index)
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 24, height: 24)
              .background(.black.opacity(0.58))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .padding(8)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .onTapGesture {
        editingMedia = MIRAEditorPresentation(media: media, replacementIndex: index)
      }
      .accessibilityLabel(index == 0 ? "Edit cover media" : "Edit media \(index + 1)")
  }

  private func removeMedia(at index: Int) {
    guard mediaItems.indices.contains(index) else { return }
    withAnimation(.snappy(duration: 0.18)) {
      mediaItems.remove(at: index)
      if mediaItems.isEmpty {
        isEditingPostDetails = false
      }
    }
  }

  private var postDetailsTextFields: some View {
    VStack(alignment: .leading, spacing: 18) {
      TextField("Add a catchy headline", text: $title)
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .submitLabel(.next)

      Rectangle()
        .fill(MIRATheme.Color.hairline.opacity(0.78))
        .frame(height: 0.7)

      TextField("Write caption with details to get more views.", text: $bodyText, axis: .vertical)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(4...8)

      Button {
        Task { await generatePostAssist() }
      } label: {
        HStack(spacing: 8) {
          if isGeneratingPostAssist {
            ProgressView()
              .scaleEffect(0.72)
          } else {
            Image(systemName: "sparkles")
              .font(.system(size: 15, weight: .bold))
          }
          Text(isGeneratingPostAssist ? "Creating ideas" : "Help me write this")
            .font(.system(size: 15, weight: .bold))
          if let category = postAssistResponse?.resolvedCategory, !category.isEmpty {
            Text(category.capitalized)
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(MIRATheme.Color.forest)
              .padding(.horizontal, 9)
              .frame(height: 24)
              .background(MIRATheme.Color.forestSoft)
              .clipShape(Capsule())
          }
        }
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(MIRATheme.Color.surfaceSoft.opacity(0.72))
        .clipShape(Capsule())
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(isGeneratingPostAssist)

      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.red.opacity(0.9))
      }
    }
  }

  private func postOptionRow(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 18) {
        Image(systemName: icon)
          .font(.system(size: icon == "ellipsis" ? 25 : 28, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 34)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 14, weight: .regular))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 27, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.82))
      }
      .frame(minHeight: 72)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MIRATheme.Color.hairline.opacity(0.72))
        .frame(height: 0.7)
    }
  }

  private var broadLocationOptionRow: some View {
    HStack(spacing: 18) {
      Image(systemName: "location.circle")
        .font(.system(size: 28, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(width: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text("Show city/country")
          .font(.system(size: 19, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(broadLocationStatusText)
          .font(.system(size: 14, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
          .truncationMode(.tail)
      }

      Spacer()

      Toggle("", isOn: $showBroadLocation)
        .labelsHidden()
        .disabled(broadLocationResolver.isResolving)
    }
    .frame(minHeight: 72)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MIRATheme.Color.hairline.opacity(0.72))
        .frame(height: 0.7)
    }
  }

  private var broadLocationStatusText: String {
    if broadLocationResolver.isResolving {
      return "Finding your city..."
    }
    if let broadLocationError, !broadLocationError.isEmpty {
      return broadLocationError
    }
    if let label = broadLocation.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
      return showBroadLocation ? label : "\(label) hidden"
    }
    return showBroadLocation ? "Tap Allow to add your city/country" : "Hidden for this post"
  }

  private var shouldPublishBroadLocation: Bool {
    showBroadLocation && broadLocation.hasVisibleLabel
  }

  @ViewBuilder
  private func postComposerMedia(_ media: MIRAPickedMedia, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
    LocalMediaThumb(media: media, width: width, height: height, cornerRadius: cornerRadius)
  }

  private var canPost: Bool {
    !mediaItems.isEmpty ||
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  @MainActor
  private func generatePostAssist() async {
    guard !isGeneratingPostAssist else { return }
    activePostDetailSheet = .aiAssist
    isGeneratingPostAssist = true
    postAssistError = nil
    defer { isGeneratingPostAssist = false }

    do {
      let cleanedTags = hashtags
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
        .filter { !$0.isEmpty }
      let mediaType = mediaItems.contains(where: { $0.kind == .video }) ? "video" : mediaItems.isEmpty ? nil : "image"
      let signals = await MIRAAutoCategoryService.analyze(
        mediaItems: mediaItems,
        title: title,
        caption: bodyText,
        hashtags: cleanedTags,
        placeName: selectedPlace?.displayName,
        location: selectedPlace?.addressText ?? broadLocation.label
      )
      let body = MIRAPostAssistBody(
        title: title,
        caption: bodyText,
        mediaType: mediaType,
        postType: selectedPlace == nil ? "general" : "place",
        hashtags: cleanedTags,
        location: selectedPlace?.addressText ?? broadLocation.label,
        placeName: selectedPlace?.displayName,
        appleVisionLabels: signals.appleVisionLabels.isEmpty ? nil : signals.appleVisionLabels,
        appleVisionCategoryGuess: signals.appleVisionCategoryGuess,
        appleVisionConfidence: signals.appleVisionConfidence
      )
      let response: MIRAPostAssistResponse = try await api.post("/ai/post-assist", body: body)
      postAssistResponse = response
    } catch {
      postAssistError = "Could not create ideas. Try again."
    }
  }

  private func submit() async {
    isPosting = true
    MIRAPerformanceTimeline.mark("post_upload_start", detail: "post")
    defer { isPosting = false }
    do {
      let uploader = MIRAMediaUploadService(api: api, target: .feedPost)
      let cleanedTags = hashtags
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
        .filter { !$0.isEmpty }
      async let autoCategorySignals = MIRAAutoCategoryService.analyze(
        mediaItems: mediaItems,
        title: title,
        caption: bodyText,
        hashtags: cleanedTags,
        placeName: selectedPlace?.displayName,
        location: selectedPlace?.addressText
      )
      var uploaded: [String] = []
      var mediaTypes: [String] = []
      var mediaDimensions: [MIRAMediaDimension] = []
      for item in mediaItems {
        uploaded.append(try await uploader.upload(item))
        mediaTypes.append(item.kind.rawValue)
        mediaDimensions.append(await item.mediaDimension())
      }
      let tagLine = cleanedTags.isEmpty ? "" : cleanedTags.map { "#\($0)" }.joined(separator: " ")
      let postContent = [bodyText.trimmingCharacters(in: .whitespacesAndNewlines), tagLine]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
      let categorySignals = await autoCategorySignals
      let taggedPayload = taggedUsers.map {
        MIRATaggedUserPayload(id: $0.id, username: $0.username, fullName: $0.fullName, profileImage: $0.profileImage)
      }
      let body = CreatePostBody(
        title: title,
        content: postContent,
        image: uploaded.first,
        images: uploaded,
        mediaTypes: mediaTypes,
        mediaDimensions: mediaDimensions,
        editorOverlays: editorUploadMetadata(),
        location: selectedPlace?.addressText ?? selectedPlace?.displayName,
        displayCity: shouldPublishBroadLocation ? broadLocation.city : nil,
        displayRegion: shouldPublishBroadLocation ? broadLocation.region : nil,
        displayCountry: shouldPublishBroadLocation ? broadLocation.country : nil,
        displayLocationLabel: shouldPublishBroadLocation ? broadLocation.label : nil,
        displayLocationSource: shouldPublishBroadLocation ? broadLocation.source : "none",
        displayLocationVisibility: shouldPublishBroadLocation ? "public" : "hidden",
        postType: selectedPlace == nil ? "general" : "place",
        placeId: selectedPlace?.providerPlaceId,
        placeName: selectedPlace?.displayName,
        placeProvider: selectedPlace?.provider,
        placeProviderId: selectedPlace?.providerPlaceId,
        placeFormattedAddress: selectedPlace?.addressText,
        placeCategory: selectedPlace?.category,
        placeCity: selectedPlace?.city,
        placeRegion: selectedPlace?.region,
        placeCountry: selectedPlace?.country,
        placeLat: selectedPlace?.latitude,
        placeLng: selectedPlace?.longitude,
        taggedUsers: taggedPayload.isEmpty ? nil : taggedPayload,
        tags: cleanedTags.isEmpty ? nil : cleanedTags,
        appleVisionLabels: categorySignals.appleVisionLabels.isEmpty ? nil : categorySignals.appleVisionLabels,
        appleVisionCategoryGuess: categorySignals.appleVisionCategoryGuess,
        appleVisionConfidence: categorySignals.appleVisionConfidence,
        audioProvider: selectedAudioTrack == nil ? nil : "audius",
        audioTrackId: selectedAudioTrack?.resolvedTrackId,
        audioTitle: selectedAudioTrack?.displayTitle,
        audioArtist: selectedAudioTrack?.displayArtist,
        audioArtworkUrl: selectedAudioTrack?.artworkUrl,
        audioStreamUrl: selectedAudioTrack?.streamUrl,
        audioStartTime: selectedAudioTrack == nil ? nil : 0,
        audioDuration: selectedAudioTrack.map { min(max($0.duration ?? 15, 5), 30) },
        visibility: "public",
        clientRequestId: UUID().uuidString
      )
      let _: MIRAPost = try await api.post("/posts", body: body)
      MIRAPerformanceTimeline.mark("post_upload_complete", detail: "post")
      close()
    } catch {
      MIRAPerformanceTimeline.mark("post_upload_failed", detail: "post")
      errorMessage = "Post could not be created."
    }
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  @MainActor
  private func loadPickerItems(_ items: [PhotosPickerItem]) async {
    isLoadingMedia = true
    defer {
      isLoadingMedia = false
      pickerItems = []
    }
    var loaded: [MIRAPickedMedia] = []
    var failedCount = 0
    for item in items {
      guard let data = try? await item.loadTransferable(type: Data.self) else {
        failedCount += 1
        continue
      }
      let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
      loaded.append(MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType))
    }
    if failedCount > 0 {
      errorMessage = failedCount == 1 ? "One media item could not be loaded." : "\(failedCount) media items could not be loaded."
    } else {
      errorMessage = nil
    }
    mediaItems.append(contentsOf: loaded)
    if !loaded.isEmpty {
      withAnimation(.snappy(duration: 0.2)) {
        isEditingPostDetails = true
      }
    }
  }

  private func addCapturedMediaAndContinue(_ media: MIRAPickedMedia) {
    editedCameraMedia = nil
    mediaItems.append(media)
    withAnimation(.snappy(duration: 0.2)) {
      isEditingPostDetails = true
    }
  }

  private func returnToCapture() {
    editedCameraMedia = nil
    withAnimation(.snappy(duration: 0.2)) {
      isEditingPostDetails = false
    }
  }

  private func editorUploadMetadata() -> [MIRAEditorUploadMetadata]? {
    let metadata = mediaItems.enumerated().compactMap { index, item -> MIRAEditorUploadMetadata? in
      guard let editorMetadata = item.editorMetadata else { return nil }
      return MIRAEditorUploadMetadata(mediaIndex: index, metadata: editorMetadata)
    }
    return metadata.isEmpty ? nil : metadata
  }

  @MainActor
  private func loadBroadLocationDefaultIfNeeded() async {
    guard !hasLoadedBroadLocation else { return }
    hasLoadedBroadLocation = true
    do {
      let user: MIRAUser = try await api.get("/auth/me")
      let location = parseProfileCity(user.city)
      broadLocation = location
    } catch {
      broadLocation = MIRABroadDisplayLocation()
    }
  }

  @MainActor
  private func resolveCurrentBroadLocationForPost() async {
    broadLocationError = nil
    let previousLocation = broadLocation
    guard let location = await broadLocationResolver.resolveCurrentLocation() else {
      broadLocation = previousLocation
      broadLocationError = "Allow location to show your city/country."
      return
    }

    let lat = String(format: "%.5f", location.coordinate.latitude)
    let lng = String(format: "%.5f", location.coordinate.longitude)
    do {
      let response: MIRABroadLocationReverseResponse = try await api.get("/mapbox-locations/reverse?lat=\(lat)&lng=\(lng)")
      guard let resolved = response.location?.displayLocation, resolved.hasVisibleLabel else {
        broadLocation = previousLocation
        broadLocationError = "Could not find your city."
        return
      }
      broadLocation = resolved
      showBroadLocation = true
      broadLocationError = nil
    } catch {
      broadLocation = previousLocation
      let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
      broadLocationError = message.isEmpty ? "Mapbox city/country could not load." : message
    }
  }

  private func parseProfileCity(_ value: String?) -> MIRABroadDisplayLocation {
    let clean = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression) ?? ""
    guard !clean.isEmpty else { return MIRABroadDisplayLocation() }
    let parts = clean
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return MIRABroadDisplayLocation(
      city: parts.first,
      region: parts.count > 2 ? parts[1] : nil,
      country: parts.count > 1 ? parts.last : nil,
      label: clean,
      source: "user_profile",
      visibility: "public"
    )
  }
}

private struct PostAIAssistSheet: View {
  let response: MIRAPostAssistResponse?
  let isLoading: Bool
  let errorMessage: String?
  let onGenerate: () -> Void
  let onApplyHeadline: (String) -> Void
  let onApplyCaption: (String) -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Post Assist")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text("Caption, headline, and Discover category ideas.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }

        Spacer()

        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 38, height: 38)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }

      if isLoading {
        VStack(spacing: 13) {
          ProgressView()
          Text("Creating natural suggestions...")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
      } else if let errorMessage {
        VStack(alignment: .leading, spacing: 14) {
          Text(errorMessage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.red.opacity(0.9))
          Button(action: onGenerate) {
            Text("Try again")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 18)
              .frame(height: 42)
              .background(MIRATheme.Color.forest)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
      } else if let response {
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 22) {
            categoryRow(response)
            suggestionSection(
              title: "Headlines",
              suggestions: response.headlineSuggestions ?? [],
              applyTitle: "Use headline",
              onApply: onApplyHeadline
            )
            suggestionSection(
              title: "Captions",
              suggestions: response.captionSuggestions ?? [],
              applyTitle: "Use caption",
              onApply: onApplyCaption
            )
          }
          .padding(.bottom, 28)
        }
      } else {
        Button(action: onGenerate) {
          HStack(spacing: 9) {
            Image(systemName: "sparkles")
            Text("Generate ideas")
          }
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(MIRATheme.Color.forest)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 18)
  }

  private func categoryRow(_ response: MIRAPostAssistResponse) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "sparkles")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(MIRATheme.Color.forest)
      VStack(alignment: .leading, spacing: 3) {
        Text("Discover category")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Text(response.resolvedCategory.capitalized)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
      }
      Spacer()
      if let confidence = response.categoryConfidence {
        Text("\(Int(confidence * 100))%")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(MIRATheme.Color.forest)
          .padding(.horizontal, 9)
          .frame(height: 28)
          .background(MIRATheme.Color.forestSoft)
          .clipShape(Capsule())
      }
    }
    .padding(14)
    .background(MIRATheme.Color.surfaceSoft.opacity(0.64))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func suggestionSection(
    title: String,
    suggestions: [String],
    applyTitle: String,
    onApply: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted)

      ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
        VStack(alignment: .leading, spacing: 11) {
          Text(suggestion)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          Button {
            onApply(suggestion)
          } label: {
            Text(applyTitle)
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(MIRATheme.Color.forest)
              .frame(height: 32)
              .padding(.horizontal, 12)
              .background(MIRATheme.Color.forestSoft)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MIRATheme.Color.surfaceSoft.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
    }
  }
}

private struct MIRAAudiusMusicPickerSheet: View {
  let api: MIRAAPIClient
  @Binding var selectedTrack: MIRAAudiusTrack?
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isSearchFocused: Bool
  @State private var query = ""
  @State private var tracks: [MIRAAudiusTrack] = []
  @State private var favoriteTracks: [MIRAAudiusTrack] = []
  @State private var favoriteTrackIds: Set<String> = []
  @State private var favoriteMutationIds: Set<String> = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var previewPlayer: AVPlayer?
  @State private var previewingTrackId: String?
  @State private var previewLoadingTrackId: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          HStack(spacing: MIRATheme.Space.sm) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted)
            TextField("Search Audius music", text: $query)
              .focused($isSearchFocused)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .submitLabel(.search)
              .onSubmit { Task { await searchTracks() } }
            Button {
              query = ""
              Task { await loadTrending() }
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textMuted.opacity(query.isEmpty ? 0 : 0.75))
            }
            .disabled(query.isEmpty)
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(height: 46)
          .background(MIRATheme.Color.surfaceSoft.opacity(0.74))
          .clipShape(Capsule())

          if let selectedTrack {
            VStack(alignment: .leading, spacing: MIRATheme.Space.xs) {
              Text("Selected sound")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MIRATheme.Color.textMuted)
                .textCase(.uppercase)
              MIRAAudioPreviewButton(
                api: api,
                trackId: selectedTrack.resolvedTrackId,
                title: selectedTrack.displayTitle,
                artist: selectedTrack.displayArtist,
                artworkUrl: selectedTrack.artworkUrl,
                streamUrl: selectedTrack.streamUrl
              )
            }
          }
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, MIRATheme.Space.sm)

        if isLoading && tracks.isEmpty && favoriteTracks.isEmpty {
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(0..<8, id: \.self) { _ in
                musicSkeletonRow
              }
            }
          }
        } else if tracks.isEmpty && favoriteTracks.isEmpty && errorMessage != nil {
          VStack(spacing: MIRATheme.Space.sm) {
            Image(systemName: "music.note.list")
              .font(.system(size: 30, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.forest)
            Text(errorMessage ?? "Search for a song or pick from trending tracks.")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal, MIRATheme.Space.xl)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              if shouldShowFavoritesSection {
                musicSectionHeader("Favorite sounds")
                if favoriteTracks.isEmpty {
                  emptyFavoritesRow
                } else {
                  ForEach(favoriteTracks) { track in
                    musicTrackRow(track)
                  }
                }

                if !visibleTracks.isEmpty {
                  musicSectionHeader("Trending")
                }
              }

              if visibleTracks.isEmpty && !shouldShowFavoritesSection {
                emptySearchRow
              } else {
                ForEach(visibleTracks) { track in
                  musicTrackRow(track)
                }
              }
            }
            .padding(.bottom, MIRATheme.Space.xl)
          }
        }
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("Music")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: MIRATheme.Space.xs) {
            if selectedTrack != nil {
              Button("Remove") {
                selectedTrack = nil
                stopPreview()
              }
                .foregroundStyle(.red.opacity(0.85))
            }
            Button("Done") { close() }
              .fontWeight(.semibold)
          }
        }
      }
      .task { await loadInitialMusic() }
      .onDisappear { stopPreview() }
    }
  }

  private var shouldShowFavoritesSection: Bool {
    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var visibleTracks: [MIRAAudiusTrack] {
    guard shouldShowFavoritesSection else { return tracks }
    return tracks.filter { !favoriteTrackIds.contains($0.resolvedTrackId) }
  }

  private func musicSectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(MIRATheme.Color.textMuted)
      .textCase(.uppercase)
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, title.hasPrefix("Favorite") ? MIRATheme.Space.sm : MIRATheme.Space.md)
      .padding(.bottom, 6)
  }

  private var emptyFavoritesRow: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: "heart")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 42, height: 42)
        .background(MIRATheme.Color.forestSoft.opacity(0.72))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text("No favorite sounds yet")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text("Tap the heart on any track to save it here.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      Spacer()
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 10)
  }

  private var emptySearchRow: some View {
    VStack(spacing: MIRATheme.Space.xs) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
      Text("No tracks found")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text("Try another song, artist, or mood.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, MIRATheme.Space.xl)
  }

  private var musicSkeletonRow: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(MIRATheme.Color.forestSoft.opacity(0.75))
        .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(width: 180, height: 13)
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(MIRATheme.Color.surfaceSoft.opacity(0.72))
          .frame(width: 112, height: 11)
      }
      Spacer()
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 10)
    .redacted(reason: .placeholder)
  }

  private func musicTrackRow(_ track: MIRAAudiusTrack) -> some View {
    let trackId = track.resolvedTrackId
    let isSelected = selectedTrack?.resolvedTrackId == trackId
    let isFavorite = favoriteTrackIds.contains(trackId)
    let isMutating = favoriteMutationIds.contains(trackId)
    let isPreviewing = previewingTrackId == trackId
    let isPreviewLoading = previewLoadingTrackId == trackId

    return HStack(spacing: MIRATheme.Space.sm) {
        if let artwork = track.artworkUrl, !artwork.isEmpty {
          RemoteMediaView(url: artwork, isVideo: false)
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(MIRATheme.Color.forestSoft)
            .frame(width: 52, height: 52)
            .overlay {
              Image(systemName: "music.note")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.forest)
            }
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(track.displayTitle)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
          HStack(spacing: 6) {
            Text(track.displayArtist)
              .lineLimit(1)
            if let duration = durationText(track.duration) {
              Text("- \(duration)")
            }
          }
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        }

        Spacer(minLength: MIRATheme.Space.sm)

        Button {
          Task { await togglePreview(track) }
        } label: {
          ZStack {
            if isPreviewLoading {
              ProgressView()
                .scaleEffect(0.72)
                .tint(.white)
            } else {
              Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: isPreviewing ? 0 : 1)
            }
          }
          .frame(width: 38, height: 38)
          .background(MIRATheme.Color.textPrimary)
          .clipShape(Circle())
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(trackId.isEmpty || isPreviewLoading)

        Button {
          Task { await toggleFavorite(track) }
        } label: {
          Image(systemName: isFavorite ? "heart.fill" : "heart")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isFavorite ? Color.red.opacity(0.86) : MIRATheme.Color.textMuted)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMutating)

        Button {
          selectTrackAndClose(track)
        } label: {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(isSelected ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
  }

  @MainActor
  private func selectTrackAndClose(_ track: MIRAAudiusTrack) {
    stopPreview()
    selectedTrack = track
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    close()
  }

  @MainActor
  private func togglePreview(_ track: MIRAAudiusTrack) async {
    let trackId = track.resolvedTrackId
    guard !trackId.isEmpty else { return }
    if previewingTrackId == trackId {
      stopPreview()
      return
    }

    stopPreview()
    previewLoadingTrackId = trackId
    defer { previewLoadingTrackId = nil }
    guard let stream = await resolvePreviewURL(for: track), let url = URL(string: stream) else {
      errorMessage = "Could not preview this track."
      return
    }
    let player = AVPlayer(url: url)
    previewPlayer = player
    previewingTrackId = trackId
    player.play()
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private func resolvePreviewURL(for track: MIRAAudiusTrack) async -> String? {
    let cleanStream = track.streamUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cleanStream.isEmpty { return cleanStream }
    let encoded = encodedPathComponent(track.resolvedTrackId)
    guard !encoded.isEmpty else { return nil }
    do {
      let resolved: MIRAAudiusTrack = try await api.get("/music/audius/stream/\(encoded)")
      return resolved.streamUrl
    } catch {
      return nil
    }
  }

  @MainActor
  private func stopPreview() {
    previewPlayer?.pause()
    previewPlayer = nil
    previewingTrackId = nil
    previewLoadingTrackId = nil
  }

  @MainActor
  private func loadInitialMusic() async {
    await loadFavorites()
    await loadTrending(force: true)
  }

  @MainActor
  private func loadFavorites() async {
    do {
      let response: MIRAAudiusTrackResponse = try await api.get("/music/audius/favorites")
      favoriteTracks = response.tracks
      favoriteTrackIds = Set(response.tracks.map(\.resolvedTrackId))
    } catch {
      favoriteTracks = []
      favoriteTrackIds = []
    }
  }

  @MainActor
  private func loadTrending(force: Bool = false) async {
    guard force || !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let response: MIRAAudiusTrackResponse = try await api.get("/music/audius/trending?limit=24")
      tracks = response.tracks
      errorMessage = nil
    } catch {
      if tracks.isEmpty {
        errorMessage = "Music is temporarily unavailable."
      }
    }
  }

  @MainActor
  private func searchTracks() async {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.count < 2 {
      await loadTrending()
      return
    }
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "q", value: clean),
      URLQueryItem(name: "limit", value: "24"),
    ]
    let queryString = components.percentEncodedQuery ?? ""
    do {
      let response: MIRAAudiusTrackResponse = try await api.get("/music/audius/search?\(queryString)")
      tracks = response.tracks
      errorMessage = nil
    } catch {
      errorMessage = "Could not search music. Try again."
    }
  }

  @MainActor
  private func toggleFavorite(_ track: MIRAAudiusTrack) async {
    let trackId = track.resolvedTrackId
    guard !trackId.isEmpty, !favoriteMutationIds.contains(trackId) else { return }
    favoriteMutationIds.insert(trackId)
    defer { favoriteMutationIds.remove(trackId) }

    let wasFavorite = favoriteTrackIds.contains(trackId)
    if wasFavorite {
      favoriteTrackIds.remove(trackId)
      favoriteTracks.removeAll { $0.resolvedTrackId == trackId }
    } else {
      favoriteTrackIds.insert(trackId)
      favoriteTracks.removeAll { $0.resolvedTrackId == trackId }
      favoriteTracks.insert(track, at: 0)
    }

    do {
      if wasFavorite {
        let encoded = encodedPathComponent(trackId)
        let _: EmptyResponse = try await api.delete("/music/audius/favorites/\(encoded)")
      } else {
        let _: MIRAAudiusFavoriteSaveResponse = try await api.post(
          "/music/audius/favorites",
          body: MIRAAudiusFavoriteBody(track: track)
        )
      }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    } catch {
      if wasFavorite {
        favoriteTrackIds.insert(trackId)
        favoriteTracks.removeAll { $0.resolvedTrackId == trackId }
        favoriteTracks.insert(track, at: 0)
        errorMessage = "Could not remove this favorite."
      } else {
        favoriteTrackIds.remove(trackId)
        favoriteTracks.removeAll { $0.resolvedTrackId == trackId }
        errorMessage = "Could not save this favorite."
      }
    }
  }

  private func durationText(_ seconds: Int?) -> String? {
    guard let seconds, seconds > 0 else { return nil }
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }

  private func encodedPathComponent(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  @MainActor
  private func close() {
    stopPreview()
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }
}

private struct MIRAAudiusFavoriteBody: Encodable {
  let id: String
  let trackId: String
  let title: String
  let artist: String
  let artistId: String?
  let artistHandle: String?
  let artistProfileImage: String?
  let artworkUrl: String?
  let duration: Int?
  let genre: String?
  let playCount: Int?
  let favoriteCount: Int?

  init(track: MIRAAudiusTrack) {
    id = track.resolvedTrackId
    trackId = track.resolvedTrackId
    title = track.displayTitle
    artist = track.displayArtist
    artistId = track.artistId
    artistHandle = track.artistHandle
    artistProfileImage = track.artistProfileImage
    artworkUrl = track.artworkUrl
    duration = track.duration
    genre = track.genre
    playCount = track.playCount
    favoriteCount = track.favoriteCount
  }
}

private struct MIRAAudiusFavoriteSaveResponse: Decodable {
  let favorite: Bool
  let track: MIRAAudiusTrack?
}

private struct PostBroadLocationPickerSheet: View {
  let api: MIRAAPIClient
  @Binding var broadLocation: MIRABroadDisplayLocation
  @Binding var showBroadLocation: Bool
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isSearchFocused: Bool
  @State private var query = ""
  @State private var results: [MIRABroadLocationSearchResult] = []
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: MIRATheme.Space.md) {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(MIRATheme.Color.textMuted)
            TextField("Search city or country", text: $query)
              .textInputAutocapitalization(.words)
              .autocorrectionDisabled()
              .submitLabel(.search)
              .focused($isSearchFocused)
              .onSubmit { Task { await searchCities(for: cleanQuery) } }
            if !cleanQuery.isEmpty {
              Button {
                query = ""
                results = []
                errorMessage = nil
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.75))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(height: 48)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Capsule())

          if let label = broadLocation.label, !label.isEmpty {
            HStack(spacing: 10) {
              Image(systemName: "location.circle.fill")
                .foregroundStyle(MIRATheme.Color.forest)
              Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .lineLimit(1)
              Spacer()
              Text(showBroadLocation ? "Visible" : "Hidden")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(showBroadLocation ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
            }
            .padding(MIRATheme.Space.md)
            .background(MIRATheme.Color.surfaceSoft.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
        }
        .padding(MIRATheme.Space.md)

        ScrollView {
          LazyVStack(spacing: 10) {
            if isLoading {
              ProgressView("Finding cities...")
                .tint(MIRATheme.Color.forest)
                .frame(maxWidth: .infinity, minHeight: 64)
            } else if let errorMessage {
              placePickerMessage(errorMessage, systemImage: "exclamationmark.triangle")
            } else if cleanQuery.isEmpty {
              placePickerMessage("Search a broad city/country label like New York, USA. Exact places stay in Add place.", systemImage: "location.circle")
            } else if cleanQuery.count < 2 {
              placePickerMessage("Keep typing to search cities.", systemImage: "text.cursor")
            } else if results.isEmpty {
              placePickerMessage("No city results yet.", systemImage: "mappin.circle")
            }

            ForEach(results) { result in
              Button {
                broadLocation = result.displayLocation
                showBroadLocation = true
                close()
              } label: {
                placeRowTitle(systemImage: "location.circle.fill", name: result.resolvedLabel, subtitle: "City/country label")
              }
              .buttonStyle(.miraPress)
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.bottom, 28)
        }
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("City/country")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Hide") {
            showBroadLocation = false
            close()
          }
          .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
      .onAppear { isSearchFocused = true }
      .task(id: cleanQuery) {
        let snapshot = cleanQuery
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !Task.isCancelled else { return }
        await searchCities(for: snapshot)
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var cleanQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func placePickerMessage(_ text: String, systemImage: String) -> some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(width: 34, height: 34)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
      Text(text)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  private func placeRowTitle(systemImage: String, name: String, subtitle: String?) -> some View {
    HStack(spacing: MIRATheme.Space.md) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 42, height: 42)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }
      Spacer(minLength: MIRATheme.Space.sm)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.65))
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  @MainActor
  private func searchCities(for clean: String) async {
    guard clean.count >= 2 else {
      results = []
      errorMessage = nil
      isLoading = false
      return
    }
    isLoading = true
    do {
      let encoded = clean.addingPercentEncoding(withAllowedCharacters: urlQueryComponentAllowed) ?? clean
      let response: MIRABroadLocationSearchResponse = try await api.get("/mapbox-locations/cities?q=\(encoded)")
      guard !Task.isCancelled, clean == cleanQuery else { return }
      results = response.locations
      errorMessage = nil
      isLoading = false
    } catch {
      guard !Task.isCancelled, clean == cleanQuery else { return }
      results = []
      errorMessage = "City search could not load."
      isLoading = false
    }
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  private var urlQueryComponentAllowed: CharacterSet {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=?+")
    return allowed
  }
}

private struct PostLocationPickerSheet: View {
  let api: MIRAAPIClient
  @Binding var selectedPlace: MIRAExactPostPlace?
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var places: [MIRAExactPostPlace] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: MIRATheme.Space.md) {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(MIRATheme.Color.textMuted)
            TextField("Search Apple Maps places", text: $query)
              .textInputAutocapitalization(.words)
              .autocorrectionDisabled()
              .submitLabel(.search)
              .focused($isSearchFocused)
              .onSubmit {
                Task { await searchPlaces(for: cleanQuery) }
              }
            if !cleanQuery.isEmpty {
              Button {
                query = ""
                places = []
                isLoading = false
                errorMessage = nil
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.75))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(height: 48)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Capsule())

          if let selectedPlace {
            selectedPlacePill(selectedPlace)
          }
        }
        .padding(MIRATheme.Space.md)

        ScrollView {
          LazyVStack(spacing: 10) {
            searchStatusView

            if cleanQuery.count >= 2 {
              Button {
                selectManualPlace()
              } label: {
                placeRowTitle(
                  systemImage: "plus.circle.fill",
                  name: "Use \"\(cleanQuery)\"",
                  subtitle: "Custom place or address"
                )
              }
              .buttonStyle(.miraPress)
            }

            ForEach(places) { place in
              Button {
                selectedPlace = place
                close()
              } label: {
                placeRowTitle(systemImage: "mappin.circle.fill", name: place.displayName, subtitle: place.addressText)
              }
              .buttonStyle(.miraPress)
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.bottom, 28)
        }
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("Add place")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if selectedPlace != nil {
            Button("Remove") {
              selectedPlace = nil
              close()
            }
            .foregroundStyle(.red)
          }
        }
      }
      .onAppear {
        isSearchFocused = true
      }
      .task(id: cleanQuery) {
        let snapshot = cleanQuery
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !Task.isCancelled else { return }
        await searchPlaces(for: snapshot)
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func selectedPlacePill(_ place: MIRAExactPostPlace) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "mappin.circle.fill")
        .foregroundStyle(MIRATheme.Color.forest)
      VStack(alignment: .leading, spacing: 2) {
        Text(place.displayName)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        if let address = place.addressText {
          Text(address)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }
      Spacer()
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.forestSoft)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private var searchStatusView: some View {
    if isLoading {
      HStack(spacing: MIRATheme.Space.sm) {
        ProgressView()
          .tint(MIRATheme.Color.forest)
        Text("Finding places...")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: 62)
      .background(MIRATheme.Color.surfaceSoft.opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    } else if let errorMessage {
      placePickerMessage(errorMessage, systemImage: "exclamationmark.triangle")
    } else if cleanQuery.isEmpty {
      placePickerMessage("Search for a restaurant, gym, cafe, park, venue, or address.", systemImage: "magnifyingglass.circle")
    } else if cleanQuery.count < 2 {
      placePickerMessage("Keep typing to search places.", systemImage: "text.cursor")
    } else if places.isEmpty {
      placePickerMessage("No matching places yet. You can still use your typed place.", systemImage: "mappin.circle")
    }
  }

  private func placePickerMessage(_ text: String, systemImage: String) -> some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(width: 34, height: 34)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
      Text(text)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  private func placeRowTitle(systemImage: String, name: String, subtitle: String?) -> some View {
    HStack(spacing: MIRATheme.Space.md) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 42, height: 42)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }
      Spacer(minLength: MIRATheme.Space.sm)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.65))
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  private var cleanQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var manualPlaceId: String {
    let slug = cleanQuery
      .lowercased()
      .filter { $0.isLetter || $0.isNumber }
      .prefix(42)
    return "manual-\(slug.isEmpty ? "place" : String(slug))"
  }

  private func selectManualPlace() {
    selectedPlace = MIRAExactPostPlace(
      providerPlaceId: manualPlaceId,
      name: cleanQuery,
      formattedAddress: cleanQuery,
      latitude: nil,
      longitude: nil,
      category: "manual",
      city: nil,
      region: nil,
      country: nil
    )
    close()
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  @MainActor
  private func searchPlaces(for clean: String) async {
    guard clean.count >= 2 else {
      places = []
      errorMessage = nil
      isLoading = false
      return
    }
    isLoading = true
    do {
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = clean
      request.resultTypes = [.pointOfInterest, .address]
      let response = try await MKLocalSearch(request: request).start()
      let loaded = response.mapItems.map(MIRAExactPostPlace.init(mapItem:))
      guard !Task.isCancelled, clean == cleanQuery else { return }
      places = loaded
      errorMessage = nil
      isLoading = false
    } catch {
      guard !Task.isCancelled, clean == cleanQuery else { return }
      places = []
      errorMessage = "Apple Maps places could not load. You can still use your typed place."
      isLoading = false
    }
  }
}

private struct PostPeopleTagSheet: View {
  let api: MIRAAPIClient
  @Binding var selectedUsers: [MIRAUser]
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var users: [MIRAUser] = []
  @State private var isLoading = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(MIRATheme.Color.textMuted)
          TextField("Search people", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .frame(height: 48)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
        .padding(MIRATheme.Space.md)

        List {
          if !selectedUsers.isEmpty {
            Section("Tagged") {
              ForEach(selectedUsers) { user in
                personRow(user, selected: true)
                  .listRowBackground(MIRATheme.Color.surface)
              }
            }
          }

          Section(query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ? "Results" : "Search") {
            if isLoading {
              ProgressView()
                .frame(maxWidth: .infinity, minHeight: 58)
                .listRowBackground(MIRATheme.Color.surface)
            } else {
              ForEach(users) { user in
                personRow(user, selected: selectedUsers.contains(where: { $0.id == user.id }))
                  .listRowBackground(MIRATheme.Color.surface)
              }
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("Tag People")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { close() }
            .fontWeight(.semibold)
        }
      }
      .task(id: query) {
        try? await Task.sleep(nanoseconds: 250_000_000)
        await searchUsers()
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func personRow(_ user: MIRAUser, selected: Bool) -> some View {
    Button {
      toggle(user)
    } label: {
      HStack(spacing: MIRATheme.Space.md) {
        RemoteAvatar(url: user.profileImage, size: 44)
        VStack(alignment: .leading, spacing: 3) {
          Text(user.displayName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          if let fullName = user.fullName, fullName != user.displayName {
            Text(fullName)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(selected ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      }
      .padding(.vertical, 5)
    }
    .buttonStyle(.plain)
  }

  private func toggle(_ user: MIRAUser) {
    if let index = selectedUsers.firstIndex(where: { $0.id == user.id }) {
      selectedUsers.remove(at: index)
    } else if selectedUsers.count < 10 {
      selectedUsers.append(user)
    }
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  @MainActor
  private func searchUsers() async {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 2 else {
      users = []
      return
    }
    isLoading = true
    defer { isLoading = false }
    users = (try? await api.get("/users/search/\(clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean)")) ?? []
  }
}

private struct PostHashtagSheet: View {
  @Binding var hashtags: [String]
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var draft = ""

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
        HStack(spacing: MIRATheme.Space.sm) {
          TextField("Add tag", text: $draft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, MIRATheme.Space.md)
            .frame(height: 48)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Capsule())

          Button("Add") {
            addTag()
          }
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 74, height: 48)
          .background(canAddTag ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.45))
          .clipShape(Capsule())
          .disabled(!canAddTag)
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.md)

        if hashtags.isEmpty {
          MIRAEmptyState(title: "No tags yet", message: "Add a few tags to help people understand the post.", systemImage: "number")
            .padding(.top, MIRATheme.Space.xl)
        } else {
          LazyVStack(spacing: MIRATheme.Space.sm) {
            ForEach(hashtags, id: \.self) { tag in
              HStack {
                Text("#\(tag)")
                  .font(.system(size: 17, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                Spacer()
                Button {
                  hashtags.removeAll { $0 == tag }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(MIRATheme.Color.textMuted)
                }
                .buttonStyle(.plain)
              }
              .padding(MIRATheme.Space.md)
              .background(MIRATheme.Color.surfaceSoft.opacity(0.7))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
        }

        Spacer()
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("Tags")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { close() }
            .fontWeight(.semibold)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }

  private var canAddTag: Bool {
    normalizedDraft.count >= 1 && !hashtags.contains(normalizedDraft)
  }

  private var normalizedDraft: String {
    let raw = draft
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
      .lowercased()
    let allowed = raw.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    return String(allowed.prefix(30))
  }

  private func addTag() {
    let clean = normalizedDraft
    guard !clean.isEmpty, !hashtags.contains(clean), hashtags.count < 12 else { return }
    hashtags.append(clean)
    draft = ""
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }
}

public struct CreateNoteNativeView: View {
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var currentUser: MIRAUser?
  @State private var noteText = ""
  @State private var mediaItem: MIRAPickedMedia?
  @State private var pickerItem: PhotosPickerItem?
  @State private var gifURL = ""
  @State private var gifQuery = ""
  @State private var gifResults: [MIRAGifItem] = []
  @State private var showGIFField = false
  @State private var isPosting = false
  @State private var isLoadingMedia = false
  @State private var isSearchingGIFs = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    VStack(spacing: 0) {
      noteComposerHeader
      Divider().overlay(MIRATheme.Color.hairline)

      ScrollView {
        noteEditorContent
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.top, MIRATheme.Space.lg)
          .padding(.bottom, 140)
      }

      noteBottomBar
    }
    .background(MIRATheme.Color.surface)
    .miraScreenEnter(.modal)
    .toolbar(.hidden, for: .navigationBar)
    .task {
      await loadCurrentUser()
      restoreDraft()
    }
    .onChange(of: pickerItem) { _, newItem in
      Task { await loadPickerItem(newItem) }
    }
  }

  private var noteComposerHeader: some View {
    HStack {
      Button("Cancel") { dismiss() }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minHeight: 56)

      Spacer()

      Button("Save") {
        saveDraft()
      }
        .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(canSaveDraft ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      .frame(width: 92, height: 46)
      .background(canSaveDraft ? MIRATheme.Color.forestSoft : MIRATheme.Color.surfaceSoft.opacity(0.72))
      .clipShape(Capsule())
      .disabled(!canSaveDraft)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, MIRATheme.Space.sm)
    .background(MIRATheme.Color.surface)
  }

  private var noteEditorContent: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.md) {
      VStack(spacing: 0) {
        RemoteAvatar(url: currentUser?.profileImage, size: 48)
        Rectangle()
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(width: 5)
          .frame(minHeight: 460)
          .clipShape(Capsule())
          .padding(.top, MIRATheme.Space.sm)
        Text((currentUser?.displayName.first.map(String.init) ?? "M").uppercased())
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.45))
          .frame(width: 34, height: 34)
          .background(MIRATheme.Color.surfaceSoft.opacity(0.35))
          .clipShape(Circle())
          .padding(.top, MIRATheme.Space.sm)
      }

      VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
        Text(currentUser?.displayName ?? "karfala900")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)

        ZStack(alignment: .topLeading) {
          if noteText.isEmpty {
            Text("What's new?")
              .font(.system(size: 19, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.72))
              .padding(.top, 7)
              .allowsHitTesting(false)
          }

          TextEditor(text: $noteText)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 130)
            .padding(.leading, -5)
        }

        HStack(spacing: MIRATheme.Space.xl) {
          PhotosPicker(selection: $pickerItem, matching: .images) {
            Image(systemName: "photo")
              .font(.system(size: 24, weight: .regular))
              .frame(width: 42, height: 42)
          }

          Button {
            openGIFPicker()
          } label: {
            Text("GIF")
              .font(.system(size: 16, weight: .heavy))
              .frame(width: 56, height: 40)
              .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(lineWidth: 2.4))
          }

          if isLoadingMedia {
            ProgressView()
              .tint(MIRATheme.Color.textMuted)
          }
        }
        .foregroundStyle(MIRATheme.Color.textMuted)
        .buttonStyle(.plain)
        .padding(.top, MIRATheme.Space.sm)

        if showGIFField {
          gifSearchPanel
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        noteMediaPreview
          .padding(.top, MIRATheme.Space.sm)

        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.red)
            .padding(.top, MIRATheme.Space.xs)
        }
      }
    }
  }

  private var noteBottomBar: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: "slider.horizontal.3")
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)

      Text("Reply options")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.78)

      Spacer()

      Button {} label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(width: 46, height: 46)
          .background(MIRATheme.Color.surface)
          .overlay(Circle().stroke(MIRATheme.Color.hairline, lineWidth: 1))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      Button {
        Task { await submit() }
      } label: {
        if isPosting {
          ProgressView().tint(.white)
        } else {
          Text("Post")
            .font(.system(size: 16, weight: .semibold))
        }
      }
      .foregroundStyle(.white)
      .frame(width: 98, height: 50)
      .background(canPostNote ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.55))
      .clipShape(Capsule())
      .disabled(isPosting || !canPostNote)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.sm)
    .padding(.bottom, MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
  }

  private var gifSearchPanel: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      HStack(spacing: MIRATheme.Space.sm) {
        TextField("Search GIFs", text: $gifQuery)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(.system(size: 15, weight: .medium))
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(height: 44)
          .background(MIRATheme.Color.surfaceSoft.opacity(0.80))
          .clipShape(Capsule())
          .onSubmit { Task { await searchGIFs() } }

        Button {
          Task { await searchGIFs() }
        } label: {
          if isSearchingGIFs {
            ProgressView().tint(MIRATheme.Color.forest)
          } else {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 17, weight: .semibold))
          }
        }
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
        .buttonStyle(.plain)
      }

      if !gifResults.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MIRATheme.Space.sm) {
            ForEach(gifResults) { gif in
              Button {
                gifURL = gif.mediaUrl ?? gif.previewUrl ?? ""
              } label: {
                RemoteMediaView(url: gif.previewUrl ?? gif.mediaUrl ?? "", isVideo: false)
                  .frame(width: 92, height: 92)
                  .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous))
                  .overlay(
                    RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous)
                      .stroke((gif.mediaUrl == gifURL || gif.previewUrl == gifURL) ? MIRATheme.Color.forest : .clear, lineWidth: 2)
                  )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 2)
        }
      } else {
        Text(isSearchingGIFs ? "Loading GIFs..." : "Tap search or type a word to find GIFs.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
  }

  private func submit() async {
    isPosting = true
    MIRAPerformanceTimeline.mark("post_upload_start", detail: "note")
    defer { isPosting = false }
    do {
      let uploadedURL: String?
      if let mediaItem {
        uploadedURL = try await MIRAMediaUploadService(api: api).upload(mediaItem)
      } else {
        let cleanGIF = gifURL.trimmingCharacters(in: .whitespacesAndNewlines)
        uploadedURL = cleanGIF.isEmpty ? nil : cleanGIF
      }
      let _: MIRANote = try await api.post("/notes", body: CreateNoteBody(body: noteText, mediaUrl: uploadedURL, color: "#FFFFFF"))
      MIRAPerformanceTimeline.mark("post_upload_complete", detail: "note")
      dismiss()
    } catch {
      MIRAPerformanceTimeline.mark("post_upload_failed", detail: "note")
      errorMessage = "Note could not be created."
    }
  }

  private var canPostNote: Bool {
    noteText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ||
      mediaItem != nil ||
      !gifURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var canSaveDraft: Bool {
    canPostNote
  }

  private var noteMediaPreview: some View {
    Group {
      if let mediaItem {
        LocalMediaThumb(media: mediaItem, width: UIScreen.main.bounds.width - 94, height: 260)
      } else if !gifURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        RemoteMediaView(url: gifURL, isVideo: false)
          .frame(maxWidth: .infinity)
          .frame(height: 260)
          .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.large, style: .continuous))
      }
    }
  }

  @MainActor
  private func loadCurrentUser() async {
    guard currentUser == nil else { return }
    currentUser = try? await api.get("/auth/me")
  }

  private func saveDraft() {
    UserDefaults.standard.set(noteText, forKey: "mira.noteDraft.text")
    UserDefaults.standard.set(gifURL, forKey: "mira.noteDraft.gifURL")
  }

  private func restoreDraft() {
    guard noteText.isEmpty && gifURL.isEmpty && mediaItem == nil else { return }
    noteText = UserDefaults.standard.string(forKey: "mira.noteDraft.text") ?? ""
    gifURL = UserDefaults.standard.string(forKey: "mira.noteDraft.gifURL") ?? ""
    showGIFField = !gifURL.isEmpty
  }

  @MainActor
  private func openGIFPicker() {
    let shouldLoadInitialResults = gifResults.isEmpty
    withAnimation(.snappy(duration: 0.18)) {
      showGIFField = true
    }
    guard shouldLoadInitialResults else { return }
    if gifQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      gifQuery = "reaction"
    }
    Task { await searchGIFs() }
  }

  @MainActor
  private func searchGIFs() async {
    let clean = gifQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 2 else {
      gifResults = []
      return
    }
    isSearchingGIFs = true
    defer { isSearchingGIFs = false }
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "q", value: clean),
      URLQueryItem(name: "limit", value: "18"),
    ]
    let query = components.percentEncodedQuery ?? "q=\(clean)"
    do {
      let response: MIRAGifSearchResponse = try await api.get("/gifs/search?\(query)")
      gifResults = response.gifs
      errorMessage = nil
    } catch {
      errorMessage = "GIF search is not available yet."
    }
  }

  @MainActor
  private func loadPickerItem(_ item: PhotosPickerItem?) async {
    guard let item else { return }
    isLoadingMedia = true
    defer {
      isLoadingMedia = false
      pickerItem = nil
    }
    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
    let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
    mediaItem = MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType)
  }
}

public struct CreateStoryNativeView: View {
  let api: MIRAAPIClient
  private let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showCamera = false
  @State private var didOpenInitialCamera = false
  @State private var isPosting = false
  @State private var errorMessage: String?
  @State private var editingMedia: MIRAEditorPresentation?
  @State private var pendingStoryMedia: MIRAPickedMedia?
  @State private var selectedAudioTrack: MIRAAudiusTrack?
  @State private var showMusicPicker = false

  public init(api: MIRAAPIClient, onClose: (() -> Void)? = nil) {
    self.api = api
    self.onClose = onClose
  }

  public var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let pendingStoryMedia {
        storyPublishPage(media: pendingStoryMedia)
      } else {
        VStack {
        HStack {
          Button { close() } label: {
            Image(systemName: "xmark")
              .font(.system(size: 24, weight: .regular))
              .foregroundStyle(.white)
              .frame(width: 48, height: 48)
          }

          Spacer()
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.sm)

        Spacer()

        VStack(spacing: MIRATheme.Space.md) {
          if isPosting {
            ProgressView()
              .tint(.white)
            Text("Posting story...")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.82))
          } else if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.86))
              .multilineTextAlignment(.center)

            Button { showCamera = true } label: {
              Label("Try again", systemImage: "camera")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .padding(.horizontal, 20)
                .frame(height: 46)
                .background(.white)
                .clipShape(Capsule())
            }
          } else {
            ProgressView()
              .tint(.white)
            Text("Opening camera...")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.72))
          }
        }

        Spacer()
      }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .miraHideTabBarOnAppear()
    .navigationBarBackButtonHidden(true)
    .statusBarHidden(true)
    .miraScreenEnter(.modal)
    .onAppear {
      MIRAPlaybackCoordinator.pauseAll(reason: "story_creation_open")
    }
    .task {
      guard !didOpenInitialCamera else { return }
      didOpenInitialCamera = true
      showCamera = true
    }
    .miraFullScreenOverlay(isPresented: $showCamera, background: .black) { closeCamera in
      MIRAStoryLiveCameraView(
        dismissesOnCapture: false,
        dismissesOnCancel: false,
        onCapture: { media in
          closeCamera()
          presentStoryEditor(for: media)
        },
        onCancel: {
          closeCamera()
          DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : MIRATransitionTiming.fullScreenClose)) {
            close()
          }
        },
        onMusic: {
          showMusicPicker = true
        }
      )
      .ignoresSafeArea()
    }
    .miraFullScreenOverlay(item: $editingMedia, background: .black) { item, closeEditor in
      MIRANativeMediaEditorView(media: item.media, mode: .story, onClose: closeEditor) { edited in
        pendingStoryMedia = edited
        closeEditor()
      }
      .ignoresSafeArea()
    }
    .miraBottomSheet(isPresented: $showMusicPicker, preferredHeightFraction: 0.78) { closeSheet in
      MIRAAudiusMusicPickerSheet(api: api, selectedTrack: $selectedAudioTrack, onClose: closeSheet)
    }
  }

  private func storyPublishPage(media: MIRAPickedMedia) -> some View {
    GeometryReader { proxy in
      VStack(spacing: 0) {
        HStack {
          Button {
            pendingStoryMedia = nil
            selectedAudioTrack = nil
            errorMessage = nil
            showCamera = true
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 28, weight: .medium))
              .foregroundStyle(.white)
              .frame(width: 50, height: 50)
          }
          .buttonStyle(.plain)

          Spacer()

          Button { close() } label: {
            Image(systemName: "xmark")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 50, height: 50)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, MIRATheme.Space.sm)
        .padding(.top, proxy.safeAreaInsets.top + 4)

        LocalMediaThumb(
          media: media,
          width: min(proxy.size.width - 28, 430),
          height: min(proxy.size.height * 0.70, (proxy.size.width - 28) * 16 / 9),
          cornerRadius: 24
        )
        .padding(.top, MIRATheme.Space.sm)
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)

        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.86))
            .multilineTextAlignment(.center)
            .padding(.horizontal, MIRATheme.Space.md)
            .padding(.top, MIRATheme.Space.md)
        }

        Spacer(minLength: MIRATheme.Space.md)

        VStack(spacing: MIRATheme.Space.sm) {
          Button {
            showMusicPicker = true
          } label: {
            HStack(spacing: MIRATheme.Space.sm) {
              Image(systemName: "music.note")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(MIRATheme.Color.forest)
                .clipShape(Circle())

              VStack(alignment: .leading, spacing: 2) {
                Text(selectedAudioTrack?.displayTitle ?? "Add music")
                  .font(.system(size: 15, weight: .semibold))
                  .foregroundStyle(.white)
                  .lineLimit(1)
                Text(selectedAudioTrack?.displayArtist ?? "Search Audius tracks")
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(.white.opacity(0.68))
                  .lineLimit(1)
              }

              Spacer()

              Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, MIRATheme.Space.md)
            .frame(height: 58)
            .background(.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
          .buttonStyle(.miraPress)

          Button {
            Task { await submit(media: media) }
          } label: {
            HStack(spacing: 8) {
              if isPosting {
                ProgressView()
                  .tint(.white)
                  .scaleEffect(0.74)
              }
              Text(isPosting ? "Posting" : "Share story")
                .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(MIRATheme.Color.forest)
            .clipShape(Capsule())
          }
          .buttonStyle(.miraPress)
          .disabled(isPosting)
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 12, 26))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func submit(media: MIRAPickedMedia) async {
    isPosting = true
    MIRAPerformanceTimeline.mark("post_upload_start", detail: "story")
    defer { isPosting = false }
    do {
      let uploaded = try await MIRAMediaUploadService(api: api).upload(media)
      let _: MIRAStatusPreview = try await api.post(
        "/statuses",
        body: CreateStatusBody(
          content: "",
          image: uploaded,
          backgroundColor: "#1B4332",
          textColor: "#FFFFFF",
          visibility: "public",
          editorMetadata: media.editorMetadata,
          audioProvider: selectedAudioTrack == nil ? nil : "audius",
          audioTrackId: selectedAudioTrack?.resolvedTrackId,
          audioTitle: selectedAudioTrack?.displayTitle,
          audioArtist: selectedAudioTrack?.displayArtist,
          audioArtworkUrl: selectedAudioTrack?.artworkUrl,
          audioStreamUrl: selectedAudioTrack?.streamUrl,
          audioStartTime: selectedAudioTrack == nil ? nil : 0,
          audioDuration: selectedAudioTrack.map { min(max($0.duration ?? 15, 5), 30) }
        )
      )
      MIRAPerformanceTimeline.mark("post_upload_complete", detail: "story")
      close()
    } catch {
      MIRAPerformanceTimeline.mark("post_upload_failed", detail: "story")
      errorMessage = "Story could not be posted."
    }
  }

  private func presentStoryEditor(for media: MIRAPickedMedia) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      editingMedia = MIRAEditorPresentation(media: media)
    }
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }
}

private func composerHeader(_ title: String) -> some View {
  HStack {
    Text(title)
      .font(.system(size: 24, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
    Spacer()
  }
}

private func composerTool(_ title: String, systemImage: String) -> some View {
  HStack(spacing: 8) {
    Image(systemName: systemImage)
    Text(title)
  }
  .font(.system(size: 14, weight: .semibold))
  .foregroundStyle(MIRATheme.Color.textPrimary)
  .padding(.horizontal, MIRATheme.Space.md)
  .frame(height: 42)
  .background(MIRATheme.Color.surfaceSoft)
  .clipShape(Capsule())
}

private final class LocalVideoPlayerUIView: UIView {
  override static var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspectFill
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private struct LocalAVPlayerLayerView: UIViewRepresentable {
  let player: AVPlayer?

  func makeUIView(context: Context) -> LocalVideoPlayerUIView {
    LocalVideoPlayerUIView()
  }

  func updateUIView(_ uiView: LocalVideoPlayerUIView, context: Context) {
    uiView.playerLayer.player = player
  }
}

private struct LocalVideoPreview: View {
  let media: MIRAPickedMedia
  @Binding var isPlaying: Bool
  @State private var player: AVPlayer?
  @State private var tempURL: URL?
  @State private var failed = false

  private var signature: String {
    "\(media.fileName)-\(media.data.count)"
  }

  var body: some View {
    ZStack {
      if let player {
        LocalAVPlayerLayerView(player: player)
      } else {
        Color.black.opacity(0.9)
        if failed {
          Image(systemName: "video.slash")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
        } else {
          ProgressView()
            .tint(.white)
        }
      }
    }
    .task(id: signature) {
      await preparePlayer()
    }
    .onChange(of: isPlaying) { _, playing in
      updatePlayback(playing)
    }
    .onDisappear {
      cleanup()
    }
  }

  private func preparePlayer() async {
    cleanup()
    failed = false
    let data = media.data
    let ext = URL(fileURLWithPath: media.fileName).pathExtension.isEmpty ? "mov" : URL(fileURLWithPath: media.fileName).pathExtension
    let preparedURL = await Task.detached(priority: .utility) { () -> URL? in
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-preview-\(UUID().uuidString).\(ext)")
      do {
        try data.write(to: url, options: .atomic)
        return url
      } catch {
        return nil
      }
    }.value

    guard let preparedURL else {
      failed = true
      return
    }

    tempURL = preparedURL
    let item = AVPlayerItem(url: preparedURL)
    let nextPlayer = AVPlayer(playerItem: item)
    nextPlayer.isMuted = true
    nextPlayer.actionAtItemEnd = .pause
    player = nextPlayer
    updatePlayback(isPlaying)
  }

  private func updatePlayback(_ playing: Bool) {
    guard let player else { return }
    if playing {
      player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
      player.play()
    } else {
      player.pause()
    }
  }

  private func cleanup() {
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    if let tempURL {
      try? FileManager.default.removeItem(at: tempURL)
    }
    tempURL = nil
  }
}

private struct LocalMediaThumb: View {
  let media: MIRAPickedMedia
  var width: CGFloat = 96
  var height: CGFloat = 96
  var cornerRadius: CGFloat = 18
  @State private var isVideoPlaying = false

  var body: some View {
    ZStack {
      if media.kind == .image, let image = UIImage(data: media.data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        LocalVideoPreview(media: media, isPlaying: $isVideoPlaying)
        if !isVideoPlaying {
          Circle()
            .fill(.black.opacity(0.44))
            .frame(width: min(58, min(width, height) * 0.54), height: min(58, min(width, height) * 0.54))
          Image(systemName: "play.fill")
            .font(.system(size: min(28, min(width, height) * 0.24), weight: .bold))
            .foregroundStyle(.white)
            .offset(x: 2)
        }
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onTapGesture {
      guard media.kind == .video else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      withAnimation(.easeInOut(duration: 0.14)) {
        isVideoPlaying.toggle()
      }
    }
  }
}

private struct ComposerPreviewSheet: View {
  let title: String
  let bodyText: String
  let mediaItems: [MIRAPickedMedia]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          if let first = mediaItems.first {
            let width = UIScreen.main.bounds.width - 32
            let height = min(width * (first.kind == .video ? 16.0 / 9.0 : 1.25), UIScreen.main.bounds.height * 0.74)
            LocalMediaThumb(media: first, width: width, height: height)
          }
          if !title.isEmpty {
            Text(title)
              .font(.system(size: 24, weight: .semibold))
          }
          if !bodyText.isEmpty {
            Text(bodyText)
              .font(.system(size: 16, weight: .regular))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
        }
        .padding(MIRATheme.Space.md)
      }
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("Preview")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
  }
}
