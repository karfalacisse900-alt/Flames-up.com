import Foundation
import SwiftUI

@MainActor
final class AuraCommunityFeedModel: ObservableObject {
  @Published private(set) var posts: [AuraCommunityPost] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var hasMore = true
  @Published private(set) var errorMessage: String?

  private let api: MIRAAPIClient
  private let pageSize: Int
  private var nextOffset = 0
  private var activeQuery = ""
  private var requestGeneration = 0

  init(api: MIRAAPIClient, pageSize: Int = 30) {
    self.api = api
    self.pageSize = max(1, min(pageSize, 50))
  }

  func load(scope: AuraCommunityFeedScope, city: String, refresh: Bool = false) async {
    let query = "\(scope.rawValue)|\(city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    let queryChanged = query != activeQuery
    guard refresh || queryChanged || posts.isEmpty else { return }

    requestGeneration += 1
    let generation = requestGeneration
    activeQuery = query
    nextOffset = 0
    hasMore = true
    isLoading = true
    isLoadingMore = false
    errorMessage = nil
    if queryChanged { posts = [] }

    do {
      let loaded = try await fetchPage(scope: scope, city: city, offset: 0)
      guard generation == requestGeneration, query == activeQuery else { return }
      posts = uniquePosts(loaded.filter { $0.mode != nil })
      nextOffset = loaded.count
      hasMore = loaded.count == pageSize
    } catch {
      guard generation == requestGeneration, query == activeQuery else { return }
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "The community feed could not be loaded."
      if queryChanged { posts = [] }
    }
    guard generation == requestGeneration else { return }
    isLoading = false
  }

  func loadNextPage(scope: AuraCommunityFeedScope, city: String) async {
    let query = "\(scope.rawValue)|\(city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    guard query == activeQuery, !isLoading, !isLoadingMore, hasMore else { return }

    let generation = requestGeneration
    let offset = nextOffset
    isLoadingMore = true
    errorMessage = nil
    defer {
      if generation == requestGeneration { isLoadingMore = false }
    }

    do {
      let loaded = try await fetchPage(scope: scope, city: city, offset: offset)
      guard generation == requestGeneration, query == activeQuery else { return }
      posts = mergeUnique(existing: posts, incoming: loaded.filter { $0.mode != nil })
      nextOffset = offset + loaded.count
      hasMore = loaded.count == pageSize
    } catch {
      guard generation == requestGeneration, query == activeQuery else { return }
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "More community posts could not be loaded."
    }
  }

  private func fetchPage(scope: AuraCommunityFeedScope, city: String, offset: Int) async throws -> [AuraCommunityPost] {
    var components = URLComponents()
    components.path = "/posts/community-feed"
    components.queryItems = [
      URLQueryItem(name: "scope", value: scope.rawValue),
      URLQueryItem(name: "city", value: city),
      URLQueryItem(name: "skip", value: String(offset)),
      URLQueryItem(name: "limit", value: String(pageSize))
    ]
    guard let path = components.string else { throw MIRAAPIError.badURL }
    return try await api.get(path)
  }

  private func uniquePosts(_ values: [AuraCommunityPost]) -> [AuraCommunityPost] {
    mergeUnique(existing: [], incoming: values)
  }

  private func mergeUnique(
    existing: [AuraCommunityPost],
    incoming: [AuraCommunityPost]
  ) -> [AuraCommunityPost] {
    var seen = Set(existing.map(\.id))
    var merged = existing
    for post in incoming where seen.insert(post.id).inserted {
      merged.append(post)
    }
    return merged
  }
}

/// Aura Home is exclusively the real social/community feed. Receipt, wallet, proof, and
/// blockchain state stay in their dedicated tabs.
public struct AuraHomeView: View {
  let api: MIRAAPIClient
  let currentUser: MIRAUser

  @StateObject private var model: AuraCommunityFeedModel
  @State private var scope: AuraCommunityFeedScope = .city
  @State private var isCreatingPost = false

  private let cityName = "New York City"

  public init(api: MIRAAPIClient, currentUser: MIRAUser) {
    self.api = api
    self.currentUser = currentUser
    _model = StateObject(wrappedValue: AuraCommunityFeedModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        feedHeader
        ScrollView {
          LazyVStack(spacing: 14) {
            feedContent
          }
          .padding(.horizontal, 16)
          .padding(.top, 14)
          .padding(.bottom, 30)
        }
        .refreshable { await model.load(scope: scope, city: cityName, refresh: true) }
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .task(id: scope) {
        await model.load(scope: scope, city: cityName, refresh: true)
      }
      .fullScreenCover(isPresented: $isCreatingPost) {
        AuraCreateCommunityPostView(api: api, currentUser: currentUser) {
          isCreatingPost = false
          Task { await model.load(scope: scope, city: cityName, refresh: true) }
        }
      }
    }
  }

  private var feedHeader: some View {
    HStack(alignment: .bottom, spacing: 24) {
      feedScopeButton(.friends, title: "Friends")
      feedScopeButton(.city, title: cityName)
      Spacer(minLength: 8)
      Button {
        isCreatingPost = true
      } label: {
        Image(systemName: "person.crop.circle.badge.plus")
          .font(.title2.weight(.semibold))
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.circle)
      .tint(MIRATheme.Color.textPrimary)
      .accessibilityLabel("Create post")
    }
    .padding(.horizontal, 18)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(MIRATheme.Color.surface)
  }

  private func feedScopeButton(_ value: AuraCommunityFeedScope, title: String) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.18)) { scope = value }
    } label: {
      VStack(spacing: 7) {
        Text(title)
          .font(.title3)
          .fontWeight(scope == value ? .bold : .semibold)
          .foregroundStyle(scope == value ? MIRATheme.Color.auraViolet : MIRATheme.Color.textSecondary)
        Rectangle()
          .fill(scope == value ? MIRATheme.Color.auraViolet : Color.clear)
          .frame(height: 3)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(scope == value ? AccessibilityTraits.isSelected : [])
  }

  @ViewBuilder
  private var feedContent: some View {
    if model.isLoading && model.posts.isEmpty {
      ForEach(0..<5, id: \.self) { _ in
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(height: 118)
          .physicalAuraCard()
          .redacted(reason: .placeholder)
      }
    } else if let error = model.errorMessage, model.posts.isEmpty {
      MIRAEmptyState(
        title: "Community feed unavailable",
        message: error,
        systemImage: "person.3.sequence"
      )
      .padding(.vertical, 34)
      .physicalAuraCard()
    } else if model.posts.isEmpty {
      MIRAEmptyState(
        title: scope == .friends ? "No posts from friends yet" : "No posts in \(cityName) yet",
        message: "Share something with your community or organize a meetup.",
        systemImage: "bubble.left.and.bubble.right"
      )
      .padding(.vertical, 34)
      .physicalAuraCard()
    } else {
      ForEach(model.posts) { post in
        feedRow(post)
          .onAppear {
            guard post.id == model.posts.last?.id else { return }
            Task { await model.loadNextPage(scope: scope, city: cityName) }
          }
      }
      if model.isLoadingMore {
        ProgressView("Loading more posts…")
          .font(.footnote)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .padding(.vertical, 12)
      }
    }
  }

  @ViewBuilder
  private func feedRow(_ post: AuraCommunityPost) -> some View {
    if post.mode == .meetup {
      NavigationLink {
        AuraMeetupDetailView(api: api, post: post)
      } label: {
        AuraMeetupFeedCard(post: post)
      }
      .buttonStyle(.plain)
    } else {
      NavigationLink {
        AuraSmallPostDetailLoaderView(api: api, postID: post.id)
      } label: {
        AuraSmallPostFeedCard(post: post)
      }
      .buttonStyle(.plain)
    }
  }
}
