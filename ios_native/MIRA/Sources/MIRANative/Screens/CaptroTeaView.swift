import SwiftUI
import UIKit

struct CaptroTeaDestination: Decodable, Hashable {
  let source: String
  let id: String

  var detailPath: String? {
    guard ["activity", "business"].contains(source), UUID(uuidString: id) != nil else { return nil }
    return "/tea/\(source)/\(id)"
  }
}

struct CaptroTeaEntry: Decodable, Hashable, Identifiable {
  let id, kind, name, status, color, timestamp: String
  let icon: String?
  let destination: CaptroTeaDestination

  var typeLabel: String {
    switch kind {
    case "club": return "Club"
    case "event": return "Event"
    case "meetup": return "Meetup"
    case "offer": return "Offer"
    case "reservation": return "Reservation"
    default: return "Business"
    }
  }

  var statusLabel: String? {
    switch status {
    case "sold_out": return "Sold out"
    case "paused": return "Orders paused"
    default: return nil
    }
  }

  var palette: CaptroTeaPalette { CaptroTeaPalette(rawValue: color) ?? .sand }
  var symbol: String {
    switch icon {
    case "people": return "person.3.fill"
    case "calendar": return "calendar"
    case "ticket": return "ticket"
    case "storefront": return "storefront"
    default: return "mappin"
    }
  }
}

struct CaptroTeaPage: Decodable {
  let items: [CaptroTeaEntry]
  let nextCursor: String?
}

struct CaptroTeaDetails: Decodable {
  let item: CaptroTeaEntry
  let post: MIRAPost?
  let commerce: CaptroCommerceDetails?
  let business: CaptroBusiness?
  let linkedEvents: [CaptroTeaEntry]?
}

enum CaptroTeaPalette: String {
  case sage, navy, lilac, sand, sky

  var color: Color {
    switch self {
    case .sage: return Color(red: 0.57, green: 0.73, blue: 0.53)
    case .navy: return Color(red: 0.13, green: 0.22, blue: 0.42)
    case .lilac: return Color(red: 0.89, green: 0.79, blue: 0.92)
    case .sand: return Color(red: 0.95, green: 0.91, blue: 0.84)
    case .sky: return Color(red: 0.80, green: 0.88, blue: 0.97)
    }
  }

  var ink: Color { self == .navy ? .white : Color(white: 0.07) }
  var iconBackground: Color { .white.opacity(self == .navy ? 0.22 : 0.80) }
}

@MainActor struct CaptroTeaView: View {
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  let close: () -> Void

  @State private var entries: [CaptroTeaEntry] = []
  @State private var path = NavigationPath()
  @State private var section = "Conversations"
  @State private var composing = false
  @State private var created: CaptroTeaConversation?
  @State private var cursor: String?
  @State private var loading = false
  @State private var didLoad = false
  @State private var error: String?
  @State private var receivedAt: Date?
  @State private var filter = "All"
  @State private var city = ""
  @State private var cityDraft = ""
  @State private var choosingCity = false
  @State private var followingUnavailable = false
  @State private var requestID: UUID?
  @State private var citySnapshots: [String: ActivitySnapshot] = [:]
  private struct ActivitySnapshot {
    let entries: [CaptroTeaEntry]
    let cursor: String?
    let receivedAt: Date?
    let loaded: Bool
  }
  private var queryKey: String { api.presentationScope + ":" + city }
  private var activityViewportKey: String { "tea-list:" + queryKey + ":" + filter }


  init(api: MIRAAPIClient, viewerID: String?, signIn: @escaping () -> Void, close: @escaping () -> Void) {
    self.api = api; self.viewerID = viewerID; self.signIn = signIn; self.close = close
    let cached = api.teaDetails.cachedListing()
    _entries = State(initialValue: cached?.entries ?? [])
    _cursor = State(initialValue: cached?.cursor)
    _didLoad = State(initialValue: cached != nil)
    _receivedAt = State(initialValue: cached?.receivedAt)
  }

  private var discoveryEntries: [CaptroTeaEntry] {
    entries.filter { entry in
      guard entry.destination.source != "business" else { return false }
      if filter == "Clubs" { return entry.kind == "club" }
      if filter == "Events" { return ["event", "meetup"].contains(entry.kind) }
      return true
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 0) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(["All", "Following", "Clubs", "Events", "Nearby"], id: \.self) { item in
              Button { selectFilter(item) } label: {
                Text(item).font(.subheadline.weight(filter == item ? .semibold : .regular))
                  .foregroundStyle(filter == item ? CaptroTeaStyle.accent : MIRATheme.Color.textPrimary)
                  .padding(.horizontal, 14).padding(.vertical, 8)
                  .background(filter == item ? CaptroTeaStyle.accent.opacity(0.13) : MIRATheme.Color.surfaceSoft, in: Capsule())
                  .frame(minHeight: 44)
              }.buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                .accessibilityIdentifier("tea.filter." + item.lowercased())
            }
          }.padding(.horizontal, 16)
        }.padding(.vertical, 8)
        HStack {
          Text(section == "Conversations" ? "Conversations" : city.isEmpty ? "Clubs & Events" : "Activities in " + city)
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          if !city.isEmpty { Button("Change city") { cityDraft = city; choosingCity = true }.font(.caption).frame(minHeight: 44) }
        }.padding(.horizontal, 16).padding(.bottom, 4)
        Divider()
        ZStack {
      List {
        if discoveryEntries.isEmpty {
          if loading || (!didLoad && error == nil) {
            listRow { ProgressView("Loading Tea").frame(maxWidth: .infinity).padding(.vertical, 16) }
          } else if let error {
            listRow { status(message: error, button: "Retry") { Task { await load(reset: true) } } }
          } else if cursor == nil {
            listRow { Text("No activities to show yet.").foregroundStyle(.secondary).padding(.vertical, 16) }
          }
        }
        ForEach(discoveryEntries) { entry in
          listRow {
            Button { if path.isEmpty { path.append(entry) } } label: { CaptroTeaRow(entry: entry) }
              .background(CaptroFeedViewportMarker(owner: api.teaDetails.listViewport,
                postID: entry.id, feed: activityViewportKey).allowsHitTesting(false))
              .buttonStyle(.plain)
              .accessibilityHint("Opens \(entry.typeLabel.lowercased()) details")
              .accessibilityIdentifier("tea.row." + entry.id)
          }
        }
        if let cursor, error == nil {
          listRow {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
              .accessibilityLabel("Loading more activities")
              .task(id: cursor + section + queryKey) { if section == "Clubs & Events" { await load(reset: false) } }
          }
        } else if !discoveryEntries.isEmpty, let error {
          listRow { status(message: error, button: "Retry") { Task { await load(reset: cursor == nil) } } }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(MIRATheme.Color.appBackground)
      .accessibilityIdentifier("tea.list")
      .refreshable { await load(reset: true) }
      .onAppear {
        api.teaDetails.listViewport.select(activityViewportKey)
        api.teaDetails.listViewport.updateOrder(discoveryEntries.map(\.id))
        api.teaDetails.listViewport.setActive(section == "Clubs & Events")
      }
      .onDisappear { api.teaDetails.listViewport.setActive(false) }
      .onChange(of: section) { _, section in api.teaDetails.listViewport.setActive(section == "Clubs & Events") }
      .onChange(of: entries) { _, _ in api.teaDetails.listViewport.updateOrder(discoveryEntries.map(\.id)) }
      .onChange(of: activityViewportKey) { _, key in
        api.teaDetails.listViewport.select(key)
        api.teaDetails.listViewport.updateOrder(discoveryEntries.map(\.id))
      }
      .opacity(section == "Clubs & Events" ? 1 : 0)
      .allowsHitTesting(section == "Clubs & Events")
      .accessibilityHidden(section != "Clubs & Events")
      CaptroTeaConversationsList(api: api, active: section == "Conversations", created: created) { post in
        if path.isEmpty { path.append(post) }
      }
        .id(api.presentationScope)
        .opacity(section == "Conversations" ? 1 : 0)
        .allowsHitTesting(section == "Conversations")
        .accessibilityHidden(section != "Conversations")
        }
      }.background(MIRATheme.Color.appBackground)
      .navigationTitle("Tea")
      .miraNavigationSurface()
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .principal) { CaptroTeaHeading() }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button { if viewerID == nil { signIn() } else { composing = true } } label: { Label("New Tea post", systemImage: "square.and.pencil") }
              .accessibilityIdentifier("tea.compose")
            Button("Conversations") { selectFilter("All") }
            Button("All clubs, events & activities") { switchCity(""); filter = "Activities"; section = "Clubs & Events" }
              .accessibilityIdentifier("tea.activities")
          } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("Tea menu").accessibilityIdentifier("tea.menu")
        }
        ToolbarItem(placement: .topBarLeading) {
          Button(action: close) {
            Image(systemName: "chevron.backward").frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel("Back to Home")
          .accessibilityIdentifier("tea.back.home")
        }
      }
      .navigationDestination(for: CaptroTeaEntry.self) { entry in
        if entry.kind == "club", entry.destination.source == "activity" {
          CaptroTeaClubDestination(entry: entry, api: api, viewerID: viewerID, signIn: signIn)
        } else { CaptroTeaDetailView(entry: entry, api: api, viewerID: viewerID, signIn: signIn).tint(MIRATheme.Color.accent) }
      }
      .navigationDestination(for: CaptroTeaConversation.self) { post in
        CaptroTeaConversationDetail(post: post, api: api, viewerID: viewerID, signIn: signIn)
      }
      .sheet(isPresented: $composing) {
        CaptroTeaComposer(api: api) { post in created = post; path.append(post) }
      }
      .task(id: section + queryKey) {
        if section == "Clubs & Events", receivedAt.map({ Date().timeIntervalSince($0) >= 30 }) != false {
          await load(reset: true)
        }
      }
      .alert("Following", isPresented: $followingUnavailable) { Button("OK", role: .cancel) {} } message: {
        Text("Tea does not yet support filtering conversations by followed accounts. Your current list has not changed.")
      }
      .alert("Nearby activities", isPresented: $choosingCity) {
        TextField("City", text: $cityDraft)
        Button("Cancel", role: .cancel) {}
        Button("Show activities") {
          let value = cityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
          if !value.isEmpty { switchCity(value); filter = "Nearby"; section = "Clubs & Events" }
        }
      } message: { Text("Choose a city for clubs, events and activities. This does not request your precise location or filter conversation posts.") }
      .tint(CaptroTeaStyle.accent)
      .onChange(of: viewerID) { _, _ in
        requestID = nil; loading = false; citySnapshots = [:]; city = ""; filter = "All"; section = "Conversations"
        path = NavigationPath(); entries = []; cursor = nil; didLoad = false; receivedAt = nil; created = nil; composing = false
        api.teaConversations.invalidate()
      }
    }
    #if DEBUG
    // Tea is a full-screen presentation: inject the isolated fixture size here,
    // since the presenting Home host's override is not inherited on every OS.
    .transformEnvironment(\.dynamicTypeSize) { size in
      if ProcessInfo.processInfo.arguments.contains("--captro-tea-review"),
         ProcessInfo.processInfo.arguments.contains("--captro-quality-large-text") { size = .accessibility2 }
    }
    #endif
  }

  private func selectFilter(_ item: String) {
    if item == "Following" { followingUnavailable = true; return }
    if item == "Nearby" { cityDraft = city; choosingCity = true; return }
    switchCity("")
    filter = item
    section = item == "All" ? "Conversations" : "Clubs & Events"
  }

  private func switchCity(_ next: String) {
    let normalized = next.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard city != normalized else { return }
    if citySnapshots.count >= 8, let oldest = citySnapshots.keys.sorted().first { citySnapshots.removeValue(forKey: oldest) }
    citySnapshots[city] = ActivitySnapshot(entries: entries, cursor: cursor, receivedAt: receivedAt, loaded: didLoad)
    requestID = nil; loading = false; error = nil
    city = normalized
    let snapshot = citySnapshots[city]
    entries = snapshot?.entries ?? []; cursor = snapshot?.cursor
    receivedAt = snapshot?.receivedAt; didLoad = snapshot?.loaded ?? false
  }

  private func listRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
  }

  private func status(message: String, button: String, retry: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(message).font(.subheadline).foregroundStyle(.secondary)
      Button(button, action: retry).frame(minHeight: 44)
    }.padding(.vertical, 10)
  }

  @MainActor private func load(reset: Bool) async {
    guard !loading, reset || cursor != nil else { return }
    loading = true
    let token = UUID(); requestID = token
    let expectedQuery = queryKey
    let owner = api.presentationScope
    error = nil
    defer { if requestID == token { loading = false; requestID = nil } }
    var params: [URLQueryItem] = []
    if !reset, let cursor { params.append(URLQueryItem(name: "cursor", value: cursor)) }
    if !city.isEmpty { params.append(URLQueryItem(name: "city", value: city)) }
    var path = URLComponents()
    path.path = "/tea"
    if !params.isEmpty { path.queryItems = params }
    do {
      let result: CaptroTeaPage = try await api.get(path.string ?? "/tea")
      try Task.checkCancellation()
      guard owner == api.presentationScope, requestID == token, queryKey == expectedQuery else { return }
      var seen = Set(reset ? [] : entries.map(\.id))
      let unique = result.items.filter { seen.insert($0.id).inserted }
      entries = reset ? unique : entries + unique
      cursor = result.nextCursor
      didLoad = true
      receivedAt = Date()
      if city.isEmpty { api.teaDetails.saveListing(entries, cursor: cursor) }
    } catch is CancellationError {
    } catch MIRAAPIError.server(_, let code, _) where code == "TEA_INVALID_PAGE" && !reset {
      guard requestID == token, queryKey == expectedQuery else { return }
      cursor = nil
      error = "Refresh Tea to start again."
    } catch {
      guard owner == api.presentationScope, requestID == token, queryKey == expectedQuery, !Task.isCancelled, !CaptroRefreshFailure.isCancellation(error) else { return }
      self.error = CaptroRefreshFailure.message(error, content: "activities", cached: !entries.isEmpty)
    }
  }
}

private struct CaptroTeaRow: View {
  let entry: CaptroTeaEntry

  var body: some View {
    HStack(spacing: 10) {
      TeaIcon(symbol: entry.symbol, palette: entry.palette)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          Text(entry.name).font(.subheadline.weight(.bold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 4)
          TeaTimestamp(entry: entry)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(entry.name).font(.subheadline.weight(.bold)).fixedSize(horizontal: false, vertical: true)
          TeaTimestamp(entry: entry)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .padding(.vertical, 16)
    .frame(minHeight: 64)
    .overlay(alignment: .bottom) { Divider() }
    .contentShape(Rectangle())
  }
}

struct TeaIcon: View {
  let symbol: String
  let palette: CaptroTeaPalette
  var body: some View {
    Image(systemName: symbol).font(.subheadline.weight(.semibold))
      .foregroundStyle(palette.ink)
      .frame(width: 29, height: 29)
      .background(palette.color, in: Circle())
      .accessibilityHidden(true)
  }
}

private struct TeaTimestamp: View {
  let entry: CaptroTeaEntry
  var body: some View {
    if let status = entry.statusLabel {
      Text(status).font(.caption)
    } else if let date = captroBusinessDate(entry.timestamp) {
      Text(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
        .font(.caption)
    }
  }
}

@MainActor
struct CaptroTeaDetailView: View {
  let entry: CaptroTeaEntry
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  @State private var detail: CaptroTeaDetails?
  @State private var commerceModel: PostDetailModel?
  @State private var error: String?
  @State private var unavailable = false
  @State private var loading = false
  private let viewport: CaptroFeedViewport
  @Environment(\.scenePhase) private var scenePhase

  init(entry: CaptroTeaEntry, api: MIRAAPIClient, viewerID: String?, signIn: @escaping () -> Void) {
    self.entry = entry; self.api = api; self.viewerID = viewerID; self.signIn = signIn
    viewport = api.teaDetails.viewport(for: entry)
    let cached = api.teaDetails.snapshot(for: entry)
    _detail = State(initialValue: cached)
    _commerceModel = State(initialValue: cached.flatMap { Self.model(for: $0, api: api, viewerID: viewerID) })
  }

  private static func model(for detail: CaptroTeaDetails, api: MIRAAPIClient, viewerID: String?) -> PostDetailModel? {
    guard let post = detail.post, let commerce = detail.commerce else { return nil }
    let model = PostDetailModel(post: post, api: api)
    model.commerce = commerce; model.currentUserId = viewerID; model.didAttemptCurrentUserLoad = true
    return model
  }

  var body: some View {
    // List owns a native refresh control even when this detail fits on one page.
    // Keep the facts in one unstyled row so their geometry stays unchanged.
    List {
      VStack(alignment: .leading, spacing: 12) {
        if unavailable {
          Text("This activity is no longer available.").foregroundStyle(.secondary).padding(.top, 12)
        } else if let business = detail?.business {
          TeaEntityCard(entry: detail?.item ?? entry, location: nil, typeLabel: business.categoryName)
          VStack(spacing: 0) {
          if !business.pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Button {
            captroBusinessDirections(business.name, business.latitude, business.longitude)
          } label: {
            TeaFact(symbol: "location", value: business.pickupAddress, palette: .sky, link: true)
          }.buttonStyle(.plain).accessibilityHint("Opens walking directions")
          }
          if !business.hours.isEmpty {
            TeaFact(symbol: "clock", value: business.hours, palette: .sand)
          }
          }
          NavigationLink {
            CaptroBusinessStorefront(api: api, business: business, isGuest: viewerID == nil)
          } label: {
            Text("View Business").modifier(TeaPrimary()).accessibilityIdentifier("tea.business-action")
          }.buttonStyle(.plain)
        } else if let commerceModel {
          TeaActivityContent(entry: detail?.item ?? entry, model: commerceModel, viewerID: viewerID, signIn: signIn)
          if let events = detail?.linkedEvents, !events.isEmpty {
            Text("Club events").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(events) { event in
              NavigationLink(value: event) { CaptroTeaRow(entry: event) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tea.linked." + event.id)
            }
          }
        } else {
          TeaEntityCard(entry: entry, location: nil)
          if loading { ProgressView("Loading details").padding(.top, 8) }
        }
        if let error, !unavailable {
          Text(error).font(.subheadline).foregroundStyle(MIRATheme.Color.textSecondary)
          Button("Retry") { Task { await load(force: true) } }.frame(minHeight: 44)
            .accessibilityIdentifier("tea.detail.retry")
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .buttonStyle(.plain)
      .listRowInsets(EdgeInsets())
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
      .background(CaptroFeedViewportMarker(owner: viewport, postID: entry.id,
        feed: entry.destination.detailPath ?? entry.id).allowsHitTesting(false))
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.vertical, 0, for: .scrollContent)
    .background(MIRATheme.Color.appBackground)
    .accessibilityIdentifier("tea.detail")
    .navigationTitle("Tea")
    .navigationBarTitleDisplayMode(.inline)
    .miraNavigationSurface()
    .miraHideTabBarOnAppear()
    .task(id: entry.destination) { await load() }
    .onAppear { viewport.setActive(true) }
    .onDisappear { viewport.setActive(false) }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await load() } }
    }
    .refreshable { await load(force: true) }
    #if DEBUG
    .overlay(alignment: .bottomLeading) { TeaReviewRequestCounter() }
    #endif
  }

  @MainActor private func load(force: Bool = false) async {
    guard !loading else { return }
    loading = true
    error = nil
    defer { loading = false }
    do {
      let response = try await api.teaDetails.load(entry, force: force)
      try Task.checkCancellation()
      guard response.item.destination == entry.destination else {
        unavailable = true
        return
      }
      if let commerceModel, let commerce = response.commerce {
        // Preserve the existing action model and selections during refresh.
        if !commerceModel.isUpdatingCommerce { commerceModel.commerce = commerce }
      } else {
        commerceModel = Self.model(for: response, api: api, viewerID: viewerID)
      }
      unavailable = false
      detail = response
    } catch is CancellationError {
      if !Task.isCancelled && detail == nil { error = "Details changed. Try again." }
    } catch MIRAAPIError.server(let status, _, _) where [401, 403, 404, 410].contains(status) {
      detail = nil; commerceModel = nil; unavailable = true
    } catch MIRAAPIError.badStatus(let status) where [401, 403, 404, 410].contains(status) {
      detail = nil; commerceModel = nil; unavailable = true
    } catch {
      self.error = detail == nil ? "Could not load these details." : "Could not refresh. Showing the last loaded details."
    }
  }
}

private struct TeaActivityContent: View {
  let entry: CaptroTeaEntry
  @ObservedObject var model: PostDetailModel
  let viewerID: String?
  let signIn: () -> Void

  var body: some View {
    if let commerce = model.commerce {
      TeaEntityCard(entry: entry, location: commerce.city)
      VStack(spacing: 0) {
      if let schedule = commerce.scheduleLabel {
        TeaFact(symbol: "calendar", value: schedule, palette: .lilac)
      }
      if commerce.paymentModel == "free" {
        TeaFact(symbol: "ticket", value: "Free", palette: .sand)
      } else if let price = commerce.resolvedLowestPrice, let terms = price.stampPrice {
        let amount = ["one_time", "one-time", "once"].contains(price.billingPeriod) ? price.money : terms
        let label = commerce.prices.count > 1 ? "From \(amount)" : (entry.kind == "event" ? "\(amount) Entry" : amount)
        TeaFact(symbol: "ticket", value: label, palette: .sand)
      }
      if commerce.joinedCount > 0 && ["event", "meetup", "club"].contains(entry.kind) {
        TeaFact(symbol: "person.3.fill", value: "\(commerce.joinedCount.formatted()) \(entry.kind == "club" ? "joined" : "going")", palette: .sky)
      }
      if let remaining = commerce.remaining {
        TeaFact(symbol: "number", value: remaining == 0 ? "Sold out" : "\(remaining) spots left", palette: .sage)
      }
      if let location = commerce.address ?? commerce.locationName, !location.isEmpty {
        Button {
          let query = [location, commerce.city].compactMap { $0 }.joined(separator: ", ")
          var maps = URLComponents(string: "https://maps.apple.com/")!
          maps.queryItems = [URLQueryItem(name: "daddr", value: query)]
          if let url = maps.url { UIApplication.shared.open(url) }
        } label: { TeaFact(symbol: "location", value: location, palette: .sky, link: true) }
          .buttonStyle(.plain)
          .accessibilityHint("Opens directions")
      }
      if let end = commerce.expiresAt.flatMap(captroBusinessDate) {
        TeaFact(symbol: "clock", value: "Ends \(end.formatted(date: .abbreviated, time: .shortened))", palette: .sand)
      }
      }
      .overlay(alignment: .bottom) { Divider() }
      if viewerID == nil {
        Button("Sign in to continue", action: signIn)
          .buttonStyle(.plain)
          .modifier(TeaPrimary())
      } else {
        CaptroCommerceDetailSection(model: model, teaStyle: true)
          .sheet(item: $model.paymentConfiguration, onDismiss: refreshCheckout) { configuration in
            if let purchase = model.commercePurchase {
              CaptroPaymentSheetView(api: model.api, configuration: configuration, purchase: purchase)
            }
          }
          .sheet(item: $model.checkoutDestination, onDismiss: refreshCheckout) { destination in
            CaptroCheckoutBrowser(url: destination.url).ignoresSafeArea()
          }
      }
      if !commerce.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Divider().padding(.top, 6)
        Text("Details").font(.headline).accessibilityAddTraits(.isHeader)
        Text(commerce.description).font(.subheadline)
      }
    }
  }

  private func refreshCheckout() { Task { await model.refreshCommerceAfterCheckout() } }
}

private struct TeaEntityCard: View {
  let entry: CaptroTeaEntry
  let location: String?
  var typeLabel: String? = nil

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 8) {
        title.fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 2)
        TeaTimestamp(entry: entry)
      }
      VStack(alignment: .leading, spacing: 8) {
        title
        TeaTimestamp(entry: entry)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
  }

  private var title: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
      Text([typeLabel ?? entry.typeLabel, location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        .font(.subheadline)
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
  }
}

private struct TeaFact: View {
  let symbol: String
  let value: String
  let palette: CaptroTeaPalette
  var link = false

  var body: some View {
    HStack(spacing: 10) {
      TeaIcon(symbol: symbol, palette: palette)
      Text(value).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
      if link { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true) }
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .padding(.vertical, 7)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }
}

private struct TeaPrimary: ViewModifier {
  func body(content: Content) -> some View {
    content.font(.body.weight(.semibold)).foregroundStyle(MIRATheme.Color.onPrimary)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(MIRATheme.Color.forest, in: RoundedRectangle(cornerRadius: MIRATheme.Radius.small))
  }
}
