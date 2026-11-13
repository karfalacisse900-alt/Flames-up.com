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

struct CaptroTeaView: View {
  let api: MIRAAPIClient
  let viewerID: String?
  let city: String?
  let signIn: () -> Void
  let close: () -> Void

  @State private var entries: [CaptroTeaEntry] = []
  @State private var path: [CaptroTeaEntry] = []
  @State private var cursor: String?
  @State private var loading = false
  @State private var didLoad = false
  @State private var error: String?

  var body: some View {
    NavigationStack(path: $path) {
      List {
        if entries.isEmpty {
          if loading || (!didLoad && error == nil) {
            listRow { ProgressView("Loading Tea").frame(maxWidth: .infinity).padding(.vertical, 16) }
          } else if let error {
            listRow { status(message: error, button: "Retry") { Task { await load(reset: true) } } }
          } else if cursor == nil {
            listRow { Text("No activities to show yet.").foregroundStyle(.secondary).padding(.vertical, 16) }
          }
        }
        ForEach(entries) { entry in
          listRow {
            Button { if path.isEmpty { path.append(entry) } } label: { CaptroTeaRow(entry: entry) }
              .buttonStyle(.plain)
              .accessibilityHint("Opens \(entry.typeLabel.lowercased()) details")
              .accessibilityIdentifier("tea.row." + entry.id)
          }
        }
        if let cursor, error == nil {
          listRow {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
              .accessibilityLabel("Loading more activities")
              .task(id: cursor) { await load(reset: false) }
          }
        } else if !entries.isEmpty, let error {
          listRow { status(message: error, button: "Retry") { Task { await load(reset: cursor == nil) } } }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(MIRATheme.Color.appBackground)
      .accessibilityIdentifier("tea.list")
      .navigationTitle("Tea")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: close) {
            Image(systemName: "chevron.backward").frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel("Back to Home")
          .accessibilityIdentifier("tea.back.home")
        }
      }
      .navigationDestination(for: CaptroTeaEntry.self) { entry in
        CaptroTeaDetailView(entry: entry, api: api, viewerID: viewerID, signIn: signIn)
      }
      .refreshable { await load(reset: true) }
      .task { if !didLoad { await load(reset: true) } }
    }
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
    error = nil
    defer { loading = false }
    var params: [URLQueryItem] = []
    if !reset, let cursor { params.append(URLQueryItem(name: "cursor", value: cursor)) }
    if let city = city?.split(separator: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
       !city.isEmpty, city.count <= 80,
       city.unicodeScalars.allSatisfy({
         CharacterSet.alphanumerics.union(.nonBaseCharacters).union(CharacterSet(charactersIn: " .'-’")).contains($0)
       }) {
      params.append(URLQueryItem(name: "city", value: city))
    }
    var path = URLComponents()
    path.path = "/tea"
    if !params.isEmpty { path.queryItems = params }
    do {
      let result: CaptroTeaPage = try await api.get(path.string ?? "/tea")
      try Task.checkCancellation()
      var seen = Set(reset ? [] : entries.map(\.id))
      let unique = result.items.filter { seen.insert($0.id).inserted }
      entries = reset ? unique : entries + unique
      cursor = result.nextCursor
      didLoad = true
    } catch is CancellationError {
    } catch MIRAAPIError.server(_, let code, _) where code == "TEA_INVALID_PAGE" && !reset {
      cursor = nil
      error = "Refresh Tea to start again."
    } catch {
      self.error = "Could not load Tea. Try again."
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
    .foregroundStyle(entry.palette.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .frame(minHeight: 48)
    .background(entry.palette.color, in: RoundedRectangle(cornerRadius: 13))
    .contentShape(Rectangle())
  }
}

private struct TeaIcon: View {
  let symbol: String
  let palette: CaptroTeaPalette
  var body: some View {
    Image(systemName: symbol).font(.subheadline.weight(.semibold))
      .foregroundStyle(palette.ink)
      .frame(width: 29, height: 29)
      .background(palette.iconBackground, in: Circle())
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

private struct CaptroTeaDetailView: View {
  let entry: CaptroTeaEntry
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  @State private var detail: CaptroTeaDetails?
  @State private var commerceModel: PostDetailModel?
  @State private var error: String?
  @State private var unavailable = false
  @State private var loading = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if unavailable {
          Text("This activity is no longer available.").foregroundStyle(.secondary).padding(.top, 12)
        } else if let business = detail?.business {
          TeaEntityCard(entry: detail?.item ?? entry, location: nil, typeLabel: business.categoryName)
          Button {
            captroBusinessDirections(business.name, business.latitude, business.longitude)
          } label: {
            TeaFact(symbol: "location", value: business.pickupAddress, palette: .sky, link: true)
          }.buttonStyle(.plain).accessibilityHint("Opens walking directions")
          if !business.hours.isEmpty {
            TeaFact(symbol: "clock", value: business.hours, palette: .sand)
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
          if let error {
            Text(error).font(.subheadline).foregroundStyle(.secondary)
            Button("Retry") { Task { await load() } }.frame(minHeight: 44)
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
    }
    .background(MIRATheme.Color.appBackground)
    .navigationTitle("Tea")
    .navigationBarTitleDisplayMode(.inline)
    .miraHideTabBarOnAppear()
    .task { if detail == nil && !unavailable { await load() } }
  }

  @MainActor private func load() async {
    guard let path = entry.destination.detailPath else { unavailable = true; return }
    loading = true
    error = nil
    defer { loading = false }
    do {
      let response: CaptroTeaDetails = try await api.get(path)
      try Task.checkCancellation()
      guard response.item.destination == entry.destination else {
        unavailable = true
        return
      }
      if let post = response.post, let commerce = response.commerce {
        let model = PostDetailModel(post: post, api: api)
        model.commerce = commerce
        model.currentUserId = viewerID
        model.didAttemptCurrentUserLoad = true
        commerceModel = model
      } else if response.business == nil {
        unavailable = true
        return
      }
      detail = response
    } catch is CancellationError {
    } catch MIRAAPIError.server(let status, _, _) where status == 404 {
      unavailable = true
    } catch {
      self.error = "Could not load these details."
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
    .foregroundStyle(entry.palette.ink)
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    .background(entry.palette.color, in: RoundedRectangle(cornerRadius: 15))
  }

  private var title: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
      Text([typeLabel ?? entry.typeLabel, location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        .font(.subheadline)
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
    .foregroundStyle(palette.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .frame(minHeight: 44)
    .background(palette.color, in: RoundedRectangle(cornerRadius: 13))
    .contentShape(Rectangle())
  }
}

private struct TeaPrimary: ViewModifier {
  func body(content: Content) -> some View {
    content.font(.body.weight(.semibold)).foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 15))
  }
}
