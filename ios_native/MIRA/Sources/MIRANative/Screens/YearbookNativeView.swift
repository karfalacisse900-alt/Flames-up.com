import SwiftUI
import UIKit

@MainActor
public final class MIRAYearbookNativeModel: ObservableObject {
  @Published public private(set) var profiles: [MIRAYearbookProfile] = []
  @Published public private(set) var myProfile: MIRAYearbookProfile?
  @Published public private(set) var isLoading = false
  @Published public private(set) var isLoadingMore = false
  @Published public private(set) var hasMore = false
  @Published public private(set) var errorMessage: String?
  @Published public private(set) var datingUnavailable = false
  @Published public var selectedIntent: MIRAYearbookIntent?
  @Published public var searchText = ""
  @Published public var cityFilter = ""
  @Published public var languageFilter = ""
  @Published public var interestFilter = ""
  @Published public var ageMinimum = ""
  @Published public var ageMaximum = ""

  let api: MIRAAPIClient
  private var nextOffset = 0
  private var loadTask: Task<Void, Never>?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  deinit {
    loadTask?.cancel()
  }

  public func prepare() async {
    async let browse: Void = reload()
    async let mine: Void = loadMyProfile()
    _ = await (browse, mine)
  }

  public func reload() async {
    loadTask?.cancel()
    let task = Task { [weak self] in
      guard let self else { return }
      isLoading = profiles.isEmpty
      errorMessage = nil
      defer { isLoading = false }
      do {
        let response: MIRAYearbookDiscoverResponse = try await api.get(discoverPath(offset: 0))
        guard !Task.isCancelled else { return }
        profiles = response.profiles
        hasMore = response.hasMore
        nextOffset = response.nextOffset
        datingUnavailable = response.datingUnavailable == true
        prefetchPortraits(response.profiles)
      } catch is CancellationError {
        return
      } catch {
        if profiles.isEmpty { errorMessage = error.localizedDescription }
      }
    }
    loadTask = task
    await task.value
  }

  public func loadMoreIfNeeded(current profile: MIRAYearbookProfile) async {
    guard hasMore, !isLoadingMore, profiles.suffix(5).contains(where: { $0.id == profile.id }) else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let response: MIRAYearbookDiscoverResponse = try await api.get(discoverPath(offset: nextOffset))
      let known = Set(profiles.map(\.id))
      profiles.append(contentsOf: response.profiles.filter { !known.contains($0.id) })
      hasMore = response.hasMore
      nextOffset = response.nextOffset
      prefetchPortraits(response.profiles)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func loadMyProfile() async {
    do {
      let response: MIRAYearbookProfileResponse = try await api.get("/yearbook/me")
      myProfile = response.profile
    } catch {
      if myProfile == nil { errorMessage = error.localizedDescription }
    }
  }

  public func profileSaved(_ profile: MIRAYearbookProfile) {
    myProfile = profile
    Task { await reload() }
  }

  private func discoverPath(offset: Int) -> String {
    var components = URLComponents()
    var items: [URLQueryItem] = [
      URLQueryItem(name: "limit", value: "24"),
      URLQueryItem(name: "offset", value: String(offset)),
    ]
    if let selectedIntent { items.append(URLQueryItem(name: "intent", value: selectedIntent.rawValue)) }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
    let city = cityFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    if !city.isEmpty { items.append(URLQueryItem(name: "city", value: city)) }
    let language = languageFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    if !language.isEmpty { items.append(URLQueryItem(name: "language", value: language)) }
    let interest = interestFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    if !interest.isEmpty { items.append(URLQueryItem(name: "interest", value: interest)) }
    if let minimum = Int(ageMinimum), (16...120).contains(minimum) {
      items.append(URLQueryItem(name: "age_min", value: String(minimum)))
    }
    if let maximum = Int(ageMaximum), (16...120).contains(maximum) {
      items.append(URLQueryItem(name: "age_max", value: String(maximum)))
    }
    components.queryItems = items
    return "/yearbook/discover?\(components.percentEncodedQuery ?? "limit=24&offset=0")"
  }

  private func prefetchPortraits(_ profiles: [MIRAYearbookProfile]) {
    let urls = profiles.compactMap(\.profilePhoto)
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 720, limit: 24)
    }
  }
}

public struct MIRAYearbookNativeView: View {
  @StateObject private var model: MIRAYearbookNativeModel
  @State private var showFilters = false
  @State private var showEditor = false
  @State private var isSearchVisible = false
  @State private var searchDraft = ""
  private let api: MIRAAPIClient
  private let currentUser: MIRAUser?

  public init(api: MIRAAPIClient, currentUser: MIRAUser?) {
    self.api = api
    self.currentUser = currentUser
    _model = StateObject(wrappedValue: MIRAYearbookNativeModel(api: api))
  }

  public var body: some View {
    ZStack {
      YearbookPaperBackground()
        .ignoresSafeArea()

      ScrollView {
        LazyVStack(spacing: 0) {
          header
          intentTabs
          content
        }
      }
      .scrollIndicators(.hidden)
      .refreshable { await model.prepare() }
    }
    .navigationBarHidden(true)
    .task { await model.prepare() }
    .sheet(isPresented: $showFilters) {
      YearbookFilterSheet(
        selectedIntent: $model.selectedIntent,
        city: $model.cityFilter,
        language: $model.languageFilter,
        interest: $model.interestFilter,
        ageMinimum: $model.ageMinimum,
        ageMaximum: $model.ageMaximum
      ) {
        Task { await model.reload() }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $showEditor) {
      YearbookEditorView(api: api, currentUser: currentUser, existingProfile: model.myProfile) { profile in
        model.profileSaved(profile)
      }
    }
  }

  private var header: some View {
    VStack(spacing: 14) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("CAPTRO")
            .font(.system(size: 11, weight: .bold, design: .serif))
            .tracking(2.2)
            .foregroundStyle(MIRATheme.Color.textSecondary)
          Text("Yearbook")
            .font(.system(size: 35, weight: .bold, design: .serif))
            .foregroundStyle(MIRATheme.Color.textPrimary)
        }
        Spacer()
        Button {
          withAnimation(.easeOut(duration: 0.2)) { isSearchVisible.toggle() }
        } label: {
          Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 46, height: 46)
            .background(MIRATheme.Color.surfaceRaised)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel(isSearchVisible ? "Close search" : "Search Yearbook")

        Button { showFilters = true } label: {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 46, height: 46)
            .background(MIRATheme.Color.surfaceRaised)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel("Yearbook filters")
      }

      if isSearchVisible {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(MIRATheme.Color.textMuted)
          TextField("Name, city, school, or interest", text: $searchDraft)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit {
              model.searchText = searchDraft
              Task { await model.reload() }
            }
          if !searchDraft.isEmpty {
            Button {
              searchDraft = ""
              model.searchText = ""
              Task { await model.reload() }
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(MIRATheme.Color.textMuted)
            }
          }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(MIRATheme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      if model.myProfile == nil {
        Button { showEditor = true } label: {
          HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
              .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
              Text("Make your page")
                .font(.system(size: 16, weight: .bold))
              Text("Add only what you want people to know.")
                .font(.system(size: 13))
                .opacity(0.78)
            }
            Spacer()
            Image(systemName: "arrow.right")
          }
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .padding(15)
          .background(MIRATheme.Color.forestSoft)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.miraPress)
      } else {
        Button { showEditor = true } label: {
          Label("Edit my Yearbook page", systemImage: "pencil.line")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.miraPress)
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 14)
    .padding(.bottom, 16)
    .background(MIRATheme.Color.surface.opacity(0.94))
    .overlay(alignment: .bottom) { Divider().opacity(0.45) }
  }

  private var intentTabs: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        YearbookIntentChip(title: "All", selected: model.selectedIntent == nil) {
          model.selectedIntent = nil
          Task { await model.reload() }
        }
        ForEach(MIRAYearbookIntent.allCases, id: \.rawValue) { intent in
          YearbookIntentChip(title: intent.title, selected: model.selectedIntent == intent) {
            model.selectedIntent = intent
            Task { await model.reload() }
          }
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 13)
    }
    .scrollIndicators(.hidden)
    .background(MIRATheme.Color.surface.opacity(0.86))
  }

  @ViewBuilder
  private var content: some View {
    if model.isLoading && model.profiles.isEmpty {
      YearbookSkeletonGrid()
    } else if let error = model.errorMessage, model.profiles.isEmpty {
      VStack(spacing: 4) {
        MIRAEmptyState(title: "The Yearbook could not open", message: error, systemImage: "book.closed")
        Button("Try again") { Task { await model.prepare() } }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.forest)
      }
      .padding(.bottom, 40)
    } else if model.profiles.isEmpty {
      MIRAEmptyState(
        title: model.datingUnavailable ? "Dating discovery is off" : "No pages here yet",
        message: model.datingUnavailable
          ? "Choose Dating on your own Yearbook page and confirm you are 18 or older before browsing dating profiles."
          : (model.selectedIntent == nil ? "Create your page, then check back as more people join." : "Try another Yearbook section or clear a filter."),
        systemImage: model.datingUnavailable ? "lock.heart" : "person.2.crop.square.stack"
      )
      .padding(.top, 38)
    } else {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
        ForEach(model.profiles) { profile in
          NavigationLink {
            YearbookProfileDetailView(api: api, initialProfile: profile, currentUserID: currentUser?.id ?? "")
          } label: {
            YearbookPortraitCard(profile: profile)
          }
          .buttonStyle(.miraPress)
          .task { await model.loadMoreIfNeeded(current: profile) }
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 16)
      .padding(.bottom, 28)

      if model.isLoadingMore {
        ProgressView()
          .tint(MIRATheme.Color.forest)
          .padding(.bottom, 28)
      }
    }
  }
}

private struct YearbookIntentChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 14, weight: selected ? .bold : .medium))
        .foregroundStyle(selected ? Color.white : MIRATheme.Color.textSecondary)
        .padding(.horizontal, 15)
        .frame(height: 38)
        .background(selected ? MIRATheme.Color.forest : MIRATheme.Color.surfaceRaised)
        .clipShape(Capsule())
    }
    .buttonStyle(.miraPress)
  }
}

private struct YearbookPortraitCard: View {
  let profile: MIRAYearbookProfile

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      ZStack(alignment: .topTrailing) {
        MIRACachedImage(url: profile.profilePhoto, maxPixelSize: 720) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          ZStack {
            MIRATheme.Color.mediaPlaceholderRaised
            Image(systemName: "person.crop.square")
              .font(.system(size: 34, weight: .light))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.82, contentMode: .fit)
        .clipped()

        Image(systemName: profile.intent == .dating || profile.intent == .friendsAndDating ? "heart.fill" : "star.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(profile.intent == .dating || profile.intent == .friendsAndDating ? Color.pink : MIRATheme.Color.forest)
          .padding(8)
          .background(MIRATheme.Color.surface.opacity(0.88))
          .clipShape(Circle())
          .padding(8)
      }
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

      Text(profile.name)
        .font(.system(size: 19, weight: .bold, design: .serif))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
      HStack(spacing: 5) {
        if let age = profile.age { Text("\(age)") }
        if profile.age != nil && !profile.locationLine.isEmpty { Text("/") }
        if !profile.locationLine.isEmpty { Text(profile.locationLine) }
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(MIRATheme.Color.textSecondary)
      .lineLimit(1)

      if let firstInterest = profile.interests?.first {
        Text(firstInterest)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
          .padding(.horizontal, 9)
          .frame(height: 25)
          .background(MIRATheme.Color.forestSoft)
          .clipShape(Capsule())
      }
    }
    .padding(10)
    .background(yearbookCardColor(profile.theme))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
    .shadow(color: Color.black.opacity(0.09), radius: 8, y: 4)
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct YearbookPaperBackground: View {
  var body: some View {
    ZStack {
      MIRATheme.Color.appBackground
      LinearGradient(
        colors: [MIRATheme.Color.surfaceSoft.opacity(0.92), MIRATheme.Color.appBackground, MIRATheme.Color.forestSoft.opacity(0.38)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Canvas { context, size in
        let color = UIColor.separator.withAlphaComponent(0.045)
        for x in stride(from: 12.0, through: size.width, by: 34) {
          for y in stride(from: 14.0, through: size.height, by: 38) {
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(Color(color)))
          }
        }
      }
      .allowsHitTesting(false)
    }
  }
}

private struct YearbookSkeletonGrid: View {
  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
      ForEach(0..<6, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 10) {
          MIRATheme.Color.mediaPlaceholderRaised
            .aspectRatio(0.82, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 5))
          Capsule().fill(MIRATheme.Color.mediaPlaceholder).frame(width: 105, height: 16)
          Capsule().fill(MIRATheme.Color.mediaPlaceholderRaised).frame(width: 78, height: 10)
        }
        .padding(10)
        .background(MIRATheme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
    }
    .padding(14)
    .redacted(reason: .placeholder)
  }
}

private struct YearbookFilterSheet: View {
  @Binding var selectedIntent: MIRAYearbookIntent?
  @Binding var city: String
  @Binding var language: String
  @Binding var interest: String
  @Binding var ageMinimum: String
  @Binding var ageMaximum: String
  let onApply: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("Browse Yearbook")
          .font(.system(size: 25, weight: .bold, design: .serif))
        Spacer()
        Button { dismiss() } label: {
          Image(systemName: "xmark")
            .frame(width: 44, height: 44)
        }
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          filterLabel("Show me")
          VStack(spacing: 8) {
            filterRow(title: "Everyone", icon: "person.2", intent: nil)
            ForEach(MIRAYearbookIntent.allCases) { intent in
              filterRow(title: intent.title, icon: intent == .dating ? "heart" : "person.crop.square", intent: intent)
            }
          }

          filterLabel("Optional details")
          VStack(spacing: 10) {
            filterField("City", icon: "building.2", text: $city)
            filterField("Language", icon: "character.bubble", text: $language)
            filterField("Interest or hobby", icon: "sparkles", text: $interest)

            HStack(spacing: 10) {
              filterField("Min age", icon: "person", text: $ageMinimum, keyboard: .numberPad)
              filterField("Max age", icon: "person", text: $ageMaximum, keyboard: .numberPad)
            }
          }

          Button("Clear all filters") {
            selectedIntent = nil
            city = ""
            language = ""
            interest = ""
            ageMinimum = ""
            ageMaximum = ""
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      }
      .scrollIndicators(.hidden)

      Button {
        onApply()
        dismiss()
      } label: {
        Text("Apply")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Color.white)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(MIRATheme.Color.forest)
          .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
    }
    .padding(22)
    .background(MIRATheme.Color.surface)
  }

  private func filterLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(MIRATheme.Color.textSecondary)
      .textCase(.uppercase)
  }

  private func filterField(
    _ title: String,
    icon: String,
    text: Binding<String>,
    keyboard: UIKeyboardType = .default
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(width: 20)
      TextField(title, text: text)
        .keyboardType(keyboard)
        .textInputAutocapitalization(keyboard == .numberPad ? .never : .words)
    }
    .padding(.horizontal, 13)
    .frame(minHeight: 46)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func filterRow(title: String, icon: String, intent: MIRAYearbookIntent?) -> some View {
    Button {
      selectedIntent = intent
    } label: {
      HStack(spacing: 12) {
        Image(systemName: icon).frame(width: 24)
        Text(title).font(.system(size: 15, weight: .semibold))
        Spacer()
        Image(systemName: selectedIntent == intent ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selectedIntent == intent ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(height: 44)
    }
    .buttonStyle(.miraPress)
  }
}

@MainActor
private final class YearbookProfileDetailModel: ObservableObject {
  @Published var profile: MIRAYearbookProfile
  @Published var isLoading = false
  @Published var isWorking = false
  @Published var errorMessage: String?
  let api: MIRAAPIClient

  init(api: MIRAAPIClient, profile: MIRAYearbookProfile) {
    self.api = api
    self.profile = profile
  }

  func refresh() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let response: MIRAYearbookProfileResponse = try await api.get("/yearbook/profiles/\(profile.userId)")
      if let refreshed = response.profile { profile = refreshed }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func updateConnection() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let response: MIRAYearbookActionResponse
      switch profile.connectionStatus {
      case "request_received":
        guard let requestID = profile.connectionRequestId, !requestID.isEmpty else {
          errorMessage = "This friend request is no longer available."
          return
        }
        response = try await api.post("/friends/accept/\(requestID)", body: EmptyYearbookBody())
      case "request_sent":
        guard let requestID = profile.connectionRequestId, !requestID.isEmpty else {
          errorMessage = "This pending request is no longer available."
          return
        }
        response = try await api.delete("/friends/request/\(requestID)")
      case "connected":
        response = try await api.delete("/friends/\(profile.userId)")
      default:
        response = try await api.post("/friends/request/\(profile.userId)", body: EmptyYearbookBody())
      }
      await refresh()
      if let detail = response.detail, !detail.isEmpty { errorMessage = detail }
    } catch { errorMessage = error.localizedDescription }
  }

  func toggleInterest() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let response: MIRAYearbookActionResponse
      if profile.interestSent {
        response = try await api.delete("/yearbook/profiles/\(profile.userId)/interest")
      } else {
        response = try await api.post("/yearbook/profiles/\(profile.userId)/interest", body: EmptyYearbookBody())
      }
      await refresh()
      if response.mutual == true { errorMessage = "You found each other. Say hi when you are ready." }
    } catch { errorMessage = error.localizedDescription }
  }

  func sign(message: String) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    do {
      let _: MIRAYearbookActionResponse = try await api.post("/yearbook/profiles/\(profile.userId)/signatures", body: YearbookSignatureBody(message: message))
      await refresh()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func block() async -> Bool {
    do {
      let _: MIRAYearbookActionResponse = try await api.post("/users/\(profile.userId)/block", body: EmptyYearbookBody())
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}

private struct EmptyYearbookBody: Encodable {}
private struct YearbookSignatureBody: Encodable { let message: String }
private struct YearbookSignatureReportBody: Encodable { let reason: String; let details: String }

private struct YearbookProfileDetailView: View {
  @StateObject private var model: YearbookProfileDetailModel
  @State private var showSignatureComposer = false
  @State private var showSignatures = false
  @State private var showChat = false
  @State private var showOptions = false
  @State private var showRemoveFriendConfirmation = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var showReport = false
  @Environment(\.dismiss) private var dismiss
  private let currentUserID: String

  init(api: MIRAAPIClient, initialProfile: MIRAYearbookProfile, currentUserID: String) {
    _model = StateObject(wrappedValue: YearbookProfileDetailModel(api: api, profile: initialProfile))
    self.currentUserID = currentUserID
  }

  var body: some View {
    ZStack {
      YearbookPaperBackground().ignoresSafeArea()
      ScrollView {
        VStack(spacing: 18) {
          profilePage
          if let signatures = model.profile.signatures, !signatures.isEmpty {
            signaturePreview(signatures)
          }
          actionPanel
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 34)
      }
      .scrollIndicators(.hidden)
    }
    .navigationTitle("Yearbook")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      if !model.profile.viewerIsOwner {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showOptions = true } label: { Image(systemName: "ellipsis") }
            .accessibilityLabel("Profile options")
        }
      }
    }
    .task { await model.refresh() }
    .sheet(isPresented: $showSignatureComposer) {
      YearbookSignatureComposer(name: model.profile.name, isWorking: model.isWorking) { message in
        await model.sign(message: message)
      }
      .presentationDetents([.height(390)])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showSignatures) {
      YearbookSignaturesView(profile: model.profile, api: model.api, currentUserID: currentUserID)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $showChat) {
      ConversationNativeView(
        peerId: model.profile.userId,
        title: model.profile.name,
        api: model.api,
        currentUserId: currentUserID,
        initialAvatarURL: model.profile.profilePhoto
      )
    }
    .confirmationDialog("Profile options", isPresented: $showOptions, titleVisibility: .visible) {
      Button("Report") {
        reportTarget = MIRAReportTarget(targetType: "user", targetId: model.profile.userId, ownerUserId: model.profile.userId, title: model.profile.name, subtitle: model.profile.handle)
        showReport = true
      }
      Button("Block", role: .destructive) {
        Task { if await model.block() { dismiss() } }
      }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog("Remove friend?", isPresented: $showRemoveFriendConfirmation, titleVisibility: .visible) {
      Button("Remove Friend", role: .destructive) {
        Task { await model.updateConnection() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can send a new friend request later.")
    }
    .sheet(isPresented: $showReport) {
      if let reportTarget {
        MIRAReportSheet(target: reportTarget, api: model.api, onSubmitted: { result in
          if result.blocked { dismiss() }
        }, onClose: { showReport = false })
      }
    }
    .alert("Yearbook", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private var profilePage: some View {
    VStack(spacing: 20) {
      identityHeader
      ForEach(resolvedSectionOrder, id: \.self) { section in
        profileSection(section)
      }
    }
    .padding(18)
    .background(yearbookCardColor(model.profile.theme))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8).stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
    .shadow(color: Color.black.opacity(0.11), radius: 18, y: 8)
  }

  private var identityHeader: some View {
    HStack(alignment: .top, spacing: 18) {
      MIRACachedImage(url: model.profile.profilePhoto, maxPixelSize: 900) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        ZStack {
          MIRATheme.Color.mediaPlaceholderRaised
          Image(systemName: "person.crop.square").font(.system(size: 42, weight: .light))
        }
      }
      .frame(width: 142, height: 178)
      .clipped()
      .overlay { Rectangle().stroke(Color.white.opacity(0.88), lineWidth: 8) }
      .shadow(color: Color.black.opacity(0.13), radius: 10, y: 6)
      .rotationEffect(.degrees(-1.5))

      VStack(alignment: .leading, spacing: 8) {
        Text(model.profile.name)
          .font(.system(size: 35, weight: .bold, design: .serif))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)
        if !model.profile.handle.isEmpty {
          Text(model.profile.handle)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        if !model.profile.locationLine.isEmpty {
          Text(model.profile.locationLine)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        Text(model.profile.intent.title)
          .font(.system(size: 12, weight: .bold))
          .padding(.horizontal, 10)
          .frame(height: 29)
          .background(MIRATheme.Color.forestSoft)
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var resolvedSectionOrder: [String] {
    let allowed = MIRAYearbookProfileDraft.defaultSectionOrder
    let requested = model.profile.sectionOrder ?? []
    let valid = requested.filter { allowed.contains($0) }
    return valid + allowed.filter { !valid.contains($0) }
  }

  @ViewBuilder
  private func profileSection(_ section: String) -> some View {
    switch section {
    case "about":
      if let bio = model.profile.shortBio, !bio.isEmpty {
        YearbookPaperSection(title: "ABOUT ME", color: Color.yellow.opacity(0.22)) {
          Text(bio)
            .font(.system(size: 17, weight: .regular, design: .serif))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    case "details":
      detailsGrid
    case "interests":
      if let interests = model.profile.interests, !interests.isEmpty {
        YearbookPaperSection(title: "INTERESTS", color: Color.blue.opacity(0.18)) {
          YearbookTagFlow(values: interests)
        }
      }
    case "prompts":
      if let prompts = model.profile.prompts, !prompts.isEmpty {
        ForEach(prompts) { prompt in
          YearbookPaperSection(title: prompt.displayPrompt.uppercased(), color: Color.pink.opacity(0.16)) {
            Text(prompt.answer)
              .font(.system(size: 17, weight: .medium, design: .serif))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    case "favorites":
      if let favorites = model.profile.favorites, !favorites.isEmpty {
        favoritesSection(favorites)
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var detailsGrid: some View {
    let details = [
      YearbookDetailItem(label: "Age", value: model.profile.age.map(String.init) ?? ""),
      YearbookDetailItem(label: "Height", value: model.profile.heightCm.map { "\($0) cm" } ?? ""),
      YearbookDetailItem(label: "Job", value: model.profile.job ?? ""),
      YearbookDetailItem(label: "School", value: model.profile.school ?? ""),
      YearbookDetailItem(label: "Languages", value: (model.profile.languages ?? []).joined(separator: " / ")),
      YearbookDetailItem(label: "Mood", value: model.profile.currentMood ?? ""),
    ].filter { !$0.value.isEmpty }
    if !details.isEmpty {
      YearbookPaperSection(title: "DETAILS", color: Color.orange.opacity(0.14)) {
        VStack(spacing: 8) {
          ForEach(details) { item in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(item.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textSecondary)
                .frame(width: 78, alignment: .leading)
              Text(item.value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
    }
  }

  private func favoritesSection(_ favorites: [String: String]) -> some View {
    YearbookPaperSection(title: "FAVORITES", color: Color.green.opacity(0.14)) {
      VStack(spacing: 10) {
        ForEach(favorites.keys.sorted(), id: \.self) { key in
          if let value = favorites[key] {
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: favoriteIcon(key)).frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text(key.replacingOccurrences(of: "_", with: " ").uppercased())
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(MIRATheme.Color.textMuted)
                Text(value)
                  .font(.system(size: 15, weight: .semibold, design: .serif))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
              }
              Spacer()
            }
          }
        }
      }
    }
  }

  private func favoriteIcon(_ key: String) -> String {
    switch key {
    case "song": return "music.note"
    case "place": return "mappin"
    case "food": return "fork.knife"
    case "movie": return "film"
    case "dream_job": return "briefcase"
    default: return "heart"
    }
  }

  private func signaturePreview(_ signatures: [MIRAYearbookSignature]) -> some View {
    Button { showSignatures = true } label: {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("SIGNED BY \(model.profile.signatureCount) PEOPLE")
            .font(.system(size: 13, weight: .bold, design: .serif))
            .tracking(0.7)
          Spacer()
          Image(systemName: "arrow.right")
        }
        ForEach(signatures.prefix(3)) { signature in
          HStack(spacing: 10) {
            YearbookSmallAvatar(url: signature.profilePhoto, size: 34)
            VStack(alignment: .leading, spacing: 1) {
              Text(signature.displayName?.isEmpty == false ? signature.displayName! : signature.username ?? "Captro member")
                .font(.system(size: 14, weight: .bold))
              if let message = signature.message, !message.isEmpty {
                Text(message).font(.system(size: 13)).lineLimit(1)
              }
            }
            Spacer()
          }
        }
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(17)
      .background(MIRATheme.Color.surface)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)
    }
    .buttonStyle(.miraPress)
  }

  private var actionPanel: some View {
    VStack(spacing: 10) {
      if !model.profile.viewerIsOwner {
        HStack(spacing: 10) {
          YearbookActionButton(title: "Sign Yearbook", subtitle: "Leave your mark", icon: "pencil.and.scribble") {
            showSignatureComposer = true
          }
          YearbookActionButton(title: "Say Hi", subtitle: "Send a message", icon: "paperplane.fill", filled: true) {
            showChat = true
          }
        }

        HStack(spacing: 10) {
          YearbookActionButton(
            title: connectionTitle,
            subtitle: connectionSubtitle,
            icon: model.profile.connectionStatus == "connected" ? "checkmark" : "person.badge.plus"
          ) {
            if model.profile.connectionStatus == "connected" {
              showRemoveFriendConfirmation = true
            } else {
              Task { await model.updateConnection() }
            }
          }
          .disabled(model.isWorking)

          if model.profile.interestAvailable == true {
            YearbookActionButton(
              title: model.profile.interestMutual ? "Mutual" : (model.profile.interestSent ? "Interested" : "Interested?"),
              subtitle: model.profile.interestMutual ? "You found each other" : "Private unless mutual",
              icon: model.profile.interestSent ? "heart.fill" : "heart"
            ) {
              Task { await model.toggleInterest() }
            }
            .disabled(model.isWorking)
          }
        }
      }
    }
  }

  private var connectionTitle: String {
    switch model.profile.connectionStatus {
    case "connected": return "Friends"
    case "request_sent": return "Requested"
    case "request_received": return "Respond"
    default: return "Add Friend"
    }
  }

  private var connectionSubtitle: String {
    switch model.profile.connectionStatus {
    case "connected": return "Tap to remove"
    case "request_sent": return "Tap to cancel"
    case "request_received": return "Accept their request"
    default: return "Send a friend request"
    }
  }
}

private struct YearbookPaperSection<Content: View>: View {
  let title: String
  let color: Color
  let content: Content

  init(title: String, color: Color, @ViewBuilder content: () -> Content) {
    self.title = title
    self.color = color
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      Text(title)
        .font(.system(size: 12, weight: .bold, design: .serif))
        .tracking(0.9)
        .padding(.horizontal, 11)
        .frame(height: 27)
        .background(color)
        .rotationEffect(.degrees(-0.7))
      content
    }
    .padding(15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MIRATheme.Color.surface.opacity(0.74))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6).stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }
}

private struct YearbookDetailItem: Identifiable {
  let label: String
  let value: String
  var id: String { label }
}

private struct YearbookTagFlow: View {
  let values: [String]
  private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
      ForEach(values, id: \.self) { value in
        Text(value)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
          .padding(.horizontal, 10)
          .frame(height: 31)
          .frame(maxWidth: .infinity)
          .background(MIRATheme.Color.surfaceRaised)
          .clipShape(RoundedRectangle(cornerRadius: 5))
      }
    }
  }
}

private struct YearbookActionButton: View {
  let title: String
  let subtitle: String
  let icon: String
  var filled = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 19, weight: .semibold))
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
          Text(subtitle).font(.system(size: 10, weight: .medium)).lineLimit(1).opacity(0.72)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 13)
      .frame(maxWidth: .infinity)
      .frame(height: 62)
      .foregroundStyle(filled ? Color.white : MIRATheme.Color.textPrimary)
      .background(filled ? MIRATheme.Color.forest : MIRATheme.Color.surface)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8).stroke(filled ? Color.clear : MIRATheme.Color.hairline, lineWidth: 1)
      }
    }
    .buttonStyle(.miraPress)
  }
}

private struct YearbookSignatureComposer: View {
  let name: String
  let isWorking: Bool
  let onSubmit: (String) async -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var localWorking = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Sign \(name)'s Yearbook")
            .font(.system(size: 22, weight: .bold, design: .serif))
          Text("Leave a short mark. You can remove it later.")
            .font(.system(size: 13))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        Spacer()
        Button("Cancel") { dismiss() }
      }

      ZStack(alignment: .topLeading) {
        TextEditor(text: $message)
          .focused($focused)
          .scrollContentBackground(.hidden)
          .padding(10)
        if message.isEmpty {
          Text("Never change... or something only the two of you understand.")
            .font(.system(size: 16, design: .serif))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .padding(16)
            .allowsHitTesting(false)
        }
      }
      .frame(height: 142)
      .background(Color.yellow.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(alignment: .bottomTrailing) {
        Text("\(message.count)/160")
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textMuted)
          .padding(10)
      }
      .onChange(of: message) { _, value in
        if value.count > 160 { message = String(value.prefix(160)) }
      }

      Button {
        Task {
          localWorking = true
          let success = await onSubmit(message)
          localWorking = false
          if success { dismiss() }
        }
      } label: {
        Group {
          if localWorking || isWorking { ProgressView().tint(.white) }
          else { Text("Sign Yearbook").font(.system(size: 16, weight: .bold)) }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(MIRATheme.Color.forest)
        .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
      .disabled(localWorking || isWorking)
    }
    .padding(22)
    .background(MIRATheme.Color.surface)
    .onAppear { focused = true }
  }
}

private struct YearbookSignaturesView: View {
  let profile: MIRAYearbookProfile
  let api: MIRAAPIClient
  let currentUserID: String
  @Environment(\.dismiss) private var dismiss
  @State private var signatures: [MIRAYearbookSignature]
  @State private var isLoading = false

  init(profile: MIRAYearbookProfile, api: MIRAAPIClient, currentUserID: String) {
    self.profile = profile
    self.api = api
    self.currentUserID = currentUserID
    _signatures = State(initialValue: profile.signatures ?? [])
  }

  var body: some View {
    NavigationStack {
      List {
        if isLoading && signatures.isEmpty {
          ProgressView().frame(maxWidth: .infinity)
        } else if signatures.isEmpty {
          MIRAEmptyState(title: "No signatures yet", message: "A signed Yearbook grows one real connection at a time.", systemImage: "pencil.and.scribble")
            .listRowBackground(Color.clear)
        } else {
          ForEach(signatures) { signature in
            HStack(alignment: .top, spacing: 12) {
              YearbookSmallAvatar(url: signature.profilePhoto, size: 42)
              VStack(alignment: .leading, spacing: 3) {
                Text(signature.displayName?.isEmpty == false ? signature.displayName! : signature.username ?? "Captro member")
                  .font(.system(size: 15, weight: .bold))
                if let message = signature.message, !message.isEmpty {
                  Text(message).font(.system(size: 14, design: .serif))
                }
              }
            }
            .swipeActions {
              if signature.signerUserId == currentUserID {
                Button("Remove", role: .destructive) { Task { await remove(signature) } }
              } else if profile.viewerIsOwner {
                Button("Hide", role: .destructive) { Task { await hide(signature) } }
                Button("Report") { Task { await report(signature) } }
                Button("Block", role: .destructive) { Task { await block(signature) } }
              }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(YearbookPaperBackground())
      .navigationTitle("Signatures")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
      .task { await load() }
    }
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    let response: MIRAYearbookSignaturesResponse? = try? await api.get("/yearbook/profiles/\(profile.userId)/signatures")
    if let response { signatures = response.signatures }
  }

  private func remove(_ signature: MIRAYearbookSignature) async {
    let _: MIRAYearbookActionResponse? = try? await api.delete("/yearbook/profiles/\(profile.userId)/signatures/me")
    signatures.removeAll { $0.id == signature.id }
  }

  private func hide(_ signature: MIRAYearbookSignature) async {
    struct Body: Encodable { let status = "hidden" }
    let _: MIRAYearbookActionResponse? = try? await api.patch("/yearbook/signatures/\(signature.id)", body: Body())
    signatures.removeAll { $0.id == signature.id }
  }

  private func report(_ signature: MIRAYearbookSignature) async {
    let _: MIRAYearbookActionResponse? = try? await api.post("/yearbook/signatures/\(signature.id)/report", body: YearbookSignatureReportBody(reason: "harassment", details: "Reported from the Yearbook signature list."))
    signatures.removeAll { $0.id == signature.id }
  }

  private func block(_ signature: MIRAYearbookSignature) async {
    let _: MIRAYearbookActionResponse? = try? await api.post("/users/\(signature.signerUserId)/block", body: EmptyYearbookBody())
    signatures.removeAll { $0.signerUserId == signature.signerUserId }
  }
}

private struct YearbookSmallAvatar: View {
  let url: String?
  let size: CGFloat

  var body: some View {
    MIRACachedImage(url: url, maxPixelSize: size * 3) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      ZStack {
        MIRATheme.Color.mediaPlaceholderRaised
        Image(systemName: "person.fill").foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}

private struct YearbookEditorView: View {
  let api: MIRAAPIClient
  let currentUser: MIRAUser?
  let existingProfile: MIRAYearbookProfile?
  let onSaved: (MIRAYearbookProfile) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var draft: MIRAYearbookProfileDraft
  @State private var languagesText: String
  @State private var interestsText: String
  @State private var hobbiesText: String
  @State private var promptOne = ""
  @State private var promptTwo = ""
  @State private var ageText: String
  @State private var heightText: String
  @State private var profileUser: MIRAUser?
  @State private var showProfileEditor = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(api: MIRAAPIClient, currentUser: MIRAUser?, existingProfile: MIRAYearbookProfile?, onSaved: @escaping (MIRAYearbookProfile) -> Void) {
    self.api = api
    self.currentUser = currentUser
    self.existingProfile = existingProfile
    self.onSaved = onSaved
    let value = existingProfile.map { MIRAYearbookProfileDraft.from($0, user: currentUser) } ?? MIRAYearbookProfileDraft.empty(from: currentUser)
    _draft = State(initialValue: value)
    _languagesText = State(initialValue: value.languages.joined(separator: ", "))
    _interestsText = State(initialValue: value.interests.joined(separator: ", "))
    _hobbiesText = State(initialValue: value.hobbies.joined(separator: ", "))
    _promptOne = State(initialValue: value.prompts.first(where: { $0.promptKey == "most_likely_to" })?.answer ?? "")
    _promptTwo = State(initialValue: value.prompts.first(where: { $0.promptKey == "little_joy" })?.answer ?? "")
    _ageText = State(initialValue: value.age.map(String.init) ?? "")
    _heightText = State(initialValue: value.heightCm.map(String.init) ?? "")
    _profileUser = State(initialValue: currentUser)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          editorPreview
          intentSection
          aboutSection
          detailsSection
          interestsSection
          favoritesSection
          promptsSection
          sectionOrderSection
          themeSection
          privacySection
        }
        .padding(16)
        .padding(.bottom, 28)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(YearbookPaperBackground())
      .navigationTitle("Edit Yearbook")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Done").fontWeight(.bold) }
          }
          .disabled(isSaving)
        }
      }
      .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        Button("OK", role: .cancel) { errorMessage = nil }
      } message: { Text(errorMessage ?? "") }
      .fullScreenCover(isPresented: $showProfileEditor) {
        EditProfileNativeView(user: profileUser, api: api, onCancel: {
          showProfileEditor = false
        }) { updated in
          profileUser = updated
          showProfileEditor = false
        }
      }
    }
  }

  private var editorPreview: some View {
    HStack(spacing: 14) {
      YearbookSmallAvatar(url: profileUser?.profileImage, size: 76)
      VStack(alignment: .leading, spacing: 5) {
        Text(profileUser?.displayName ?? "Your page")
          .font(.system(size: 24, weight: .bold, design: .serif))
        Text("This is one Captro identity. Your login and username stay the same.")
          .font(.system(size: 12))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        Button("Change profile photo") { showProfileEditor = true }
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
      }
      Spacer()
    }
    .padding(16)
    .background(yearbookCardColor(MIRAYearbookTheme(rawValue: draft.themeId) ?? .classicYearbook))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)
  }

  private var intentSection: some View {
    editorSection("I'M LOOKING FOR") {
      Picker("Discovery intent", selection: $draft.discoveryIntent) {
        ForEach(MIRAYearbookIntent.allCases) { intent in Text(intent.title).tag(intent.rawValue) }
      }
      .pickerStyle(.navigationLink)

      if draft.discoveryIntent == MIRAYearbookIntent.dating.rawValue || draft.discoveryIntent == MIRAYearbookIntent.friendsAndDating.rawValue {
        Toggle("Enable private mutual interest", isOn: $draft.datingEnabled)
        Text("Dating is available only to adults 18+. Interest stays private unless both people choose it.")
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
    }
  }

  private var aboutSection: some View {
    editorSection("ABOUT ME") {
      TextField("Current mood", text: $draft.currentMood)
      TextField("A short introduction", text: $draft.shortBio, axis: .vertical)
        .lineLimit(3...6)
    }
  }

  private var detailsSection: some View {
    editorSection("DETAILS") {
      HStack {
        TextField("Age", text: $ageText)
          .keyboardType(.numberPad)
        Divider()
        TextField("Height (cm)", text: $heightText)
          .keyboardType(.numberPad)
      }
      TextField("City", text: $draft.city)
      TextField("Country", text: $draft.country)
      TextField("Job", text: $draft.job)
      TextField("School", text: $draft.school)
    }
  }

  private var interestsSection: some View {
    editorSection("INTERESTS") {
      TextField("Languages, separated by commas", text: $languagesText)
      TextField("Interests, separated by commas", text: $interestsText)
      TextField("Hobbies, separated by commas", text: $hobbiesText)
    }
  }

  private var favoritesSection: some View {
    editorSection("FAVORITES") {
      favoriteField("Favorite song", key: "song")
      favoriteField("Favorite place", key: "place")
      favoriteField("Favorite food", key: "food")
      favoriteField("Favorite movie", key: "movie")
      favoriteField("Dream job", key: "dream_job")
      favoriteField("Fun fact", key: "fun_fact")
    }
  }

  private var promptsSection: some View {
    editorSection("YEARBOOK PROMPTS") {
      TextField("Most likely to...", text: $promptOne, axis: .vertical).lineLimit(2...4)
      TextField("A small thing I love...", text: $promptTwo, axis: .vertical).lineLimit(2...4)
      Text("A few good answers feel more personal than a long questionnaire.")
        .font(.caption)
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
  }

  private var themeSection: some View {
    editorSection("PROFILE THEME") {
      Picker("Theme", selection: $draft.themeId) {
        ForEach(MIRAYearbookTheme.allCases) { theme in Text(theme.title).tag(theme.rawValue) }
      }
      .pickerStyle(.navigationLink)
    }
  }

  private var sectionOrderSection: some View {
    editorSection("PAGE ORDER") {
      Text("Move the parts that matter most to the top of your page.")
        .font(.caption)
        .foregroundStyle(MIRATheme.Color.textSecondary)

      ForEach(Array(normalizedSectionOrder.enumerated()), id: \.element) { index, section in
        HStack(spacing: 12) {
          Image(systemName: "line.3.horizontal")
            .foregroundStyle(MIRATheme.Color.textMuted)
          Text(sectionTitle(section))
            .font(.system(size: 14, weight: .semibold))
          Spacer()
          Button { moveSection(at: index, offset: -1) } label: {
            Image(systemName: "chevron.up").frame(width: 34, height: 34)
          }
          .disabled(index == 0)
          Button { moveSection(at: index, offset: 1) } label: {
            Image(systemName: "chevron.down").frame(width: 34, height: 34)
          }
          .disabled(index == normalizedSectionOrder.count - 1)
        }
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minHeight: 42)
      }
    }
  }

  private var normalizedSectionOrder: [String] {
    let allowed = MIRAYearbookProfileDraft.defaultSectionOrder
    let valid = draft.sectionOrder.filter { allowed.contains($0) }
    return valid + allowed.filter { !valid.contains($0) }
  }

  private func sectionTitle(_ section: String) -> String {
    switch section {
    case "about": return "About me"
    case "details": return "Details"
    case "interests": return "Interests"
    case "prompts": return "Yearbook prompts"
    case "favorites": return "Favorites"
    default: return section.capitalized
    }
  }

  private func moveSection(at index: Int, offset: Int) {
    var order = normalizedSectionOrder
    let target = index + offset
    guard order.indices.contains(index), order.indices.contains(target) else { return }
    order.swapAt(index, target)
    draft.sectionOrder = order
  }

  private var privacySection: some View {
    editorSection("WHO CAN SEE WHAT") {
      privacyRow("Name", field: "display_name")
      privacyRow("Photo", field: "profile_photo")
      privacyRow("Age", field: "age")
      privacyRow("City and country", field: "city")
      privacyRow("Job", field: "job")
      privacyRow("School", field: "school")
      privacyRow("Languages", field: "languages")
      privacyRow("Interests", field: "interests")
      privacyRow("Favorites", field: "favorites")
      privacyRow("Prompts", field: "prompts")
      Toggle("Show my Yearbook page", isOn: Binding(get: { draft.status == "active" }, set: { draft.status = $0 ? "active" : "hidden" }))
    }
  }

  private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      Text(title)
        .font(.system(size: 12, weight: .bold, design: .serif))
        .tracking(0.8)
        .foregroundStyle(MIRATheme.Color.textSecondary)
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay { RoundedRectangle(cornerRadius: 10).stroke(MIRATheme.Color.hairline, lineWidth: 1) }
  }

  private func favoriteField(_ title: String, key: String) -> some View {
    TextField(title, text: Binding(
      get: { draft.favorites[key] ?? "" },
      set: { value in
        if value.isEmpty { draft.favorites.removeValue(forKey: key) }
        else { draft.favorites[key] = value }
      }
    ))
  }

  private func privacyRow(_ title: String, field: String) -> some View {
    HStack {
      Text(title).font(.system(size: 14, weight: .medium))
      Spacer()
      Picker(title, selection: Binding(
        get: { draft.fieldVisibility[field] ?? "private" },
        set: { draft.fieldVisibility[field] = $0 }
      )) {
        ForEach(MIRAYearbookVisibility.allCases) { value in
          Label(value.title, systemImage: value.systemImage).tag(value.rawValue)
        }
      }
      .labelsHidden()
    }
    .frame(minHeight: 40)
  }

  private func splitList(_ value: String, max limit: Int) -> [String] {
    var seen = Set<String>()
    return value.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
      .prefix(limit)
      .map(String.init)
  }

  private func save() async {
    draft.age = Int(ageText.trimmingCharacters(in: .whitespacesAndNewlines))
    draft.heightCm = Int(heightText.trimmingCharacters(in: .whitespacesAndNewlines))
    if draft.datingEnabled && (draft.age ?? 0) < 18 {
      errorMessage = "Dating can only be enabled for adults age 18 or older."
      return
    }
    isSaving = true
    defer { isSaving = false }
    draft.languages = splitList(languagesText, max: 12)
    draft.interests = splitList(interestsText, max: 20)
    draft.hobbies = splitList(hobbiesText, max: 20)
    draft.sectionOrder = normalizedSectionOrder
    draft.prompts = [
      MIRAYearbookPromptDraft(promptKey: "most_likely_to", answer: promptOne.trimmingCharacters(in: .whitespacesAndNewlines), position: 0),
      MIRAYearbookPromptDraft(promptKey: "little_joy", answer: promptTwo.trimmingCharacters(in: .whitespacesAndNewlines), position: 1),
    ].filter { !$0.answer.isEmpty }
    do {
      let response: MIRAYearbookProfileResponse = try await api.put("/yearbook/me", body: draft)
      guard let profile = response.profile else {
        errorMessage = "The server saved an incomplete Yearbook page. Please try again."
        return
      }
      onSaved(profile)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private func yearbookCardColor(_ theme: MIRAYearbookTheme) -> Color {
  switch theme {
  case .classicYearbook: return MIRATheme.Color.surface
  case .notebook: return Color(red: 0.97, green: 0.96, blue: 0.90)
  case .y2k: return Color(red: 0.91, green: 0.94, blue: 0.98)
  case .film: return Color(red: 0.94, green: 0.91, blue: 0.84)
  case .minimal: return MIRATheme.Color.surfaceRaised
  case .vintage: return Color(red: 0.93, green: 0.87, blue: 0.75)
  case .scrapbook: return Color(red: 0.96, green: 0.91, blue: 0.83)
  }
}
