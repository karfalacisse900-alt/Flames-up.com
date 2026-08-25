import SwiftUI

@MainActor
final class AuraCommunityFeedModel: ObservableObject {
  @Published private(set) var posts: [AuraCommunityPost] = []
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?

  private let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load(scope: AuraCommunityFeedScope, city: String, refresh: Bool = false) async {
    guard !isLoading || refresh else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "New%20York%20City"
      let loaded: [AuraCommunityPost] = try await api.get(
        "/posts/community-feed?scope=\(scope.rawValue)&city=\(encodedCity)&limit=40"
      )
      posts = loaded.filter { $0.mode != nil }
    } catch {
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "The community feed could not be loaded."
      if !refresh { posts = [] }
    }
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
  }
}
