import CoreLocation
import MapKit
import SwiftUI

func captroBusinessPrice(_ amount: Int) -> String {
  CaptroMoney.format(minorUnits: amount, currency: "USD", fixedPrecision: true)
}

struct CaptroBusinessPhoto: View {
  let url: String?
  var fill = true

  var body: some View {
    GeometryReader { geometry in
      MIRACachedImage(url: url, maxPixelSize: min(1200, max(160, geometry.size.width * 3)),
                      animatesNetworkLoad: false) { image in
        image.resizable().aspectRatio(contentMode: fill ? .fill : .fit)
          .frame(width: geometry.size.width, height: geometry.size.height)
      } placeholder: {
        Rectangle().fill(Color(uiColor: .secondarySystemBackground))
          .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
      }
    }
    .clipped()
    .accessibilityHidden(true)
  }
}

struct CaptroBusinessPrimary: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.headline)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(.white)
      .background(.black.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
  }
}

final class CaptroBusinessLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published private(set) var location: CLLocationCoordinate2D?
  @Published private(set) var unavailable = false
  private let manager = CLLocationManager()
  private var requested = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
  }
  func request() {
    requested = true
    unavailable = false
    updateAuthorization()
  }
  private func updateAuthorization() {
    guard requested else { return }
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
    default: unavailable = true
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { updateAuthorization() }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    location = locations.last?.coordinate
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { unavailable = true }
}

struct CaptroBusinessDirectory: View {
  let api: MIRAAPIClient
  let isGuest: Bool
  @Environment(\.dismiss) private var dismiss
  @StateObject private var location = CaptroBusinessLocation()
  @State private var businesses: [CaptroBusiness] = []
  @State private var error: String?
  @State private var loading = false
  @State private var more = false

  var body: some View {
    List {
      Button { location.request() } label: { Label("Find businesses near me", systemImage: "location") }
      if location.unavailable { Text("Location is unavailable. You can still browse businesses.").font(.footnote) }
      if loading && businesses.isEmpty { ProgressView() }
      if let error { Text(error).foregroundStyle(.secondary) }
      if !loading && error == nil && businesses.isEmpty {
        Text("No businesses listed yet.").foregroundStyle(.secondary)
      }
      ForEach(businesses) { business in
        NavigationLink {
          CaptroBusinessStorefront(api: api, business: business, isGuest: isGuest)
        } label: {
          HStack {
            CaptroBusinessPhoto(url: business.avatarUrl).frame(width: 46, height: 46).clipShape(Circle())
            VStack(alignment: .leading) {
              Text(business.name).font(.headline)
              Text(business.categoryName).foregroundStyle(.secondary)
            }
            Spacer()
            if let miles = business.distanceMiles {
              Text(miles, format: .number.precision(.fractionLength(1))) + Text(" mi")
            }
          }
        }.accessibilityIdentifier("business.shop.\(business.id)")
      }
      if more { Button("Load more businesses") { Task { await load(reset: false) } }.disabled(loading) }
    }
    .navigationTitle("Captro Business")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
      if !isGuest {
        ToolbarItem(placement: .primaryAction) {
          NavigationLink("Your Orders") { CaptroBusinessOrders(api: api) }
        }
      }
    }
    .task(id: location.location?.latitude) { await load(reset: true) }
    .refreshable { await load(reset: true) }
    .overlay(alignment: .bottom) {
      if error != nil { Button("Retry") { Task { await load(reset: true) } }.buttonStyle(.borderedProminent).padding() }
    }
  }

  @MainActor private func load(reset: Bool) async {
    if !reset && loading { return }
    loading = true
    defer { if !Task.isCancelled { loading = false } }
    error = nil
    let coords = location.location
    let parameters = coords.map {
      let lat = ($0.latitude * 100).rounded() / 100
      let lon = ($0.longitude * 100).rounded() / 100
      return "&lat=\(lat)&lon=\(lon)"
    } ?? ""
    do {
      let page: [CaptroBusiness] = try await api.get("/businesses?offset=\(reset ? 0 : businesses.count)\(parameters)")
      try Task.checkCancellation()
      businesses = reset ? page : businesses + page.filter { row in !businesses.contains { $0.id == row.id } }
      more = page.count == 30
    } catch is CancellationError {
    } catch { self.error = error.localizedDescription }
  }
}

struct CaptroBusinessStorefront: View {
  let api: MIRAAPIClient
  let business: CaptroBusiness
  let isGuest: Bool
  @State private var products: [CaptroBusinessProduct] = []
  @State private var bag = CaptroBusinessBag()
  @State private var category: String?
  @State private var search = ""
  @State private var searchVisible = false
  @State private var loading = false
  @State private var more = false
  @State private var error: String?
  @State private var editing: CaptroBusinessProduct?
  @State private var openBagAfterProduct = false
  @State private var showsBag = false

  private var isFixture: Bool {
    #if DEBUG
    ProcessInfo.processInfo.arguments.contains("--captro-business-review")
    #else
    false
    #endif
  }
  private var bagKey: String { "captro.business.bag.\(MIRALocalJSONCache.currentScopeIdentifier).\(business.id)" }
  private var categories: [String] { Array(Set(products.map(\.category))).sorted() }
  private var visibleProducts: [CaptroBusinessProduct] {
    products.filter { (category == nil || category == $0.category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header
        if business.photos.count == 1 {
          CaptroBusinessPhoto(url: business.photos[0]).frame(height: 96).clipShape(RoundedRectangle(cornerRadius: 9))
        } else if !business.photos.isEmpty {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(Array(business.photos.enumerated()), id: \.offset) { _, photo in
                CaptroBusinessPhoto(url: photo).frame(width: 130, height: 96)
                  .clipShape(RoundedRectangle(cornerRadius: 9))
              }
            }
          }.scrollIndicators(.hidden)
        }
        HStack {
          Text("Menu").font(.headline)
          Spacer()
          Button { searchVisible.toggle() } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
            .accessibilityLabel("Search products")
        }
        if searchVisible { TextField("Search products", text: $search).textFieldStyle(.roundedBorder) }
        if !categories.isEmpty {
          ScrollView(.horizontal) {
            HStack(spacing: 7) {
              categoryButton("All", value: nil)
              ForEach(categories, id: \.self) { categoryButton($0, value: $0) }
            }
          }.scrollIndicators(.hidden)
        }
        if loading && products.isEmpty { ProgressView() }
        if let error {
          Text(error).foregroundStyle(.secondary)
          Button("Retry menu") { Task { await load(reset: true) } }
        } else if visibleProducts.isEmpty && !loading {
          Text("No products match.").foregroundStyle(.secondary)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
          ForEach(visibleProducts) { product in tile(product) }
        }
        if more { Button("Load more products") { Task { await load(reset: false) } }.disabled(loading) }
      }.padding(.horizontal, 16).padding(.bottom, 14)
    }
    .navigationBarTitleDisplayMode(.inline)
    .tint(.primary)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { showsBag = true } label: {
          Label(bag.quantity > 0 ? "Bag, \(bag.quantity) items" : "Your Bag", systemImage: "bag")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if bag.quantity > 0 {
        Button("View Bag · \(bag.quantity)") { showsBag = true }
          .buttonStyle(CaptroBusinessPrimary()).padding(.horizontal, 16).padding(.vertical, 6).background(.background)
      }
    }
    .navigationDestination(isPresented: $showsBag) {
      CaptroBusinessBagView(api: api, business: business, bag: $bag, isGuest: isGuest) { showsBag = false }
    }
    .sheet(item: $editing, onDismiss: {
      if openBagAfterProduct {
        openBagAfterProduct = false
        showsBag = true
      }
    }) { product in
      NavigationStack {
        CaptroBusinessCustomize(product: product, initial: [], quantity: 1) { choices, count in
          let current = bag.lines.first { $0.product.id == product.id && $0.selection == choices }?.quantity ?? 0
          bag.set(product: product, selection: choices, quantity: current + count)
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Back") { editing = nil } }
          ToolbarItem(placement: .primaryAction) {
            Button {
              openBagAfterProduct = true
              editing = nil
            } label: { Label("Your Bag", systemImage: "bag") }
          }
        }
      }
    }
    .task {
      if !isFixture, let bytes = UserDefaults.standard.data(forKey: bagKey),
         let saved = try? JSONDecoder().decode(CaptroBusinessBag.self, from: bytes) { bag = saved }
      await load(reset: true)
    }
    .onChange(of: bag.requestId) { _, _ in
      if !isGuest && !isFixture, let bytes = try? JSONEncoder().encode(bag) { UserDefaults.standard.set(bytes, forKey: bagKey) }
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 5) {
        Text(business.name).font(.title2.bold())
        let distance = business.distanceMiles.map { $0.formatted(.number.precision(.fractionLength(1))) + " mi · " } ?? ""
        Text(distance + business.categoryName).font(.subheadline).foregroundStyle(.secondary)
        Button {
          captroBusinessDirections(business.name, business.latitude, business.longitude)
        } label: {
          Label(business.pickupAddress, systemImage: "location").font(.subheadline)
        }.frame(minHeight: 44)
        if !business.hours.isEmpty { Text(business.hours).font(.footnote).foregroundStyle(.secondary) }
        if business.paused { Text("Orders paused").font(.footnote).foregroundStyle(.secondary) }
        if business.category == "street_food", let date = business.locationUpdatedAt.flatMap(captroBusinessDate) {
          Text("Pickup location updated \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      Spacer()
      CaptroBusinessPhoto(url: business.avatarUrl).frame(width: 44, height: 44).clipShape(Circle())
    }
  }

  private func categoryButton(_ title: String, value: String?) -> some View {
    Button { category = value } label: {
      Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(category == value ? Color.white : Color.primary)
        .background(category == value ? Color.black : Color(uiColor: .secondarySystemBackground), in: Capsule())
        .frame(minHeight: 44)
    }.buttonStyle(.plain).accessibilityAddTraits(category == value ? .isSelected : [])
  }

  private func tile(_ product: CaptroBusinessProduct) -> some View {
    let current = bag.lines.first { $0.product.id == product.id && $0.selection.isEmpty }?.quantity ?? 0
    return VStack(alignment: .leading, spacing: 4) {
      if product.isCustom {
        Button { editing = product } label: { tileContent(product) }.buttonStyle(.plain)
      } else {
        tileContent(product)
      }
      ViewThatFits(in: .horizontal) {
        HStack {
          Text(captroBusinessPrice(product.unitAmount)).font(.subheadline)
          Spacer(minLength: 0)
          tileQuantity(product, current: current)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(captroBusinessPrice(product.unitAmount)).font(.subheadline)
          tileQuantity(product, current: current)
        }
      }
    }.padding(7).background {
      RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary)
    }
  }

  @ViewBuilder
  private func tileQuantity(_ product: CaptroBusinessProduct, current: Int) -> some View {
    if product.isCustom || current == 0 {
      Button {
        if product.isCustom { editing = product }
        else { bag.set(product: product, selection: [], quantity: 1) }
      } label: {
        Image(systemName: "plus").font(.subheadline.bold()).frame(width: 28, height: 28)
          .background(.quaternary, in: Circle()).frame(width: 44, height: 44)
      }.buttonStyle(.plain)
        .accessibilityLabel(product.isCustom ? "Customize \(product.name)" : "Add \(product.name)")
        .disabled(business.paused && !product.isCustom)
    } else {
      CaptroBusinessStepper(quantity: current) { bag.set(product: product, selection: [], quantity: $0) }
    }
  }

  private func tileContent(_ product: CaptroBusinessProduct) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      CaptroBusinessPhoto(url: product.imageUrl, fill: false).frame(height: 90)
      Text(product.name).font(.subheadline.bold()).lineLimit(2)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  @MainActor private func load(reset: Bool) async {
    guard !loading else { return }
    loading = true
    defer { loading = false }
    error = nil
    do {
      let page: [CaptroBusinessProduct] = try await api.get("/businesses/\(business.id)/menu?offset=\(reset ? 0 : products.count)")
      try Task.checkCancellation()
      products = reset ? page : products + page.filter { row in !products.contains { $0.id == row.id } }
      more = page.count == 50
    } catch is CancellationError {
    } catch { self.error = error.localizedDescription }
  }
}

struct CaptroBusinessStepper: View {
  let quantity: Int
  var minimum = 0
  let change: (Int) -> Void
  var body: some View {
    HStack(spacing: 0) {
      Button { change(quantity - 1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
        .disabled(quantity <= minimum).accessibilityLabel("Decrease quantity")
      Text("\(quantity)").monospacedDigit().accessibilityLabel("Quantity \(quantity)")
      Button { change(quantity + 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
        .disabled(quantity >= 20).accessibilityLabel("Increase quantity")
    }
    .font(.subheadline.weight(.semibold)).buttonStyle(.plain)
    .background(.quaternary, in: Capsule())
  }
}

struct CaptroBusinessCustomize: View {
  let product: CaptroBusinessProduct
  let add: (Set<String>, Int) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var choices: Set<String>
  @State private var quantity: Int
  @State private var sheetGroup: CaptroBusinessGroup?

  init(product: CaptroBusinessProduct, initial: Set<String>, quantity: Int, add: @escaping (Set<String>, Int) -> Void) {
    self.product = product
    self.add = add
    _choices = State(initialValue: initial)
    _quantity = State(initialValue: quantity)
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        CaptroBusinessPhoto(url: product.imageUrl, fill: false).frame(height: 170)
        Text(product.name).font(.title2.bold())
        Text(captroBusinessPrice(product.unitAmount)).font(.headline)
        ForEach(product.groups) { group in
          VStack(alignment: .leading, spacing: 2) {
            Text(group.name).font(.headline)
            if group.minimum > 0 { Text("Choose \(group.minimum == group.maximum ? "\(group.minimum)" : "\(group.minimum)–\(group.maximum)")").font(.caption).foregroundStyle(.secondary) }
            if group.options.count > 5 {
              Button("Choose \(group.name.lowercased())") { sheetGroup = group }.frame(minHeight: 44)
              let selected = group.options.filter { choices.contains($0.id) }.map(\.name)
              if !selected.isEmpty { Text(selected.joined(separator: ", ")).font(.caption) }
            } else if group.maximum == 1 && group.name.caseInsensitiveCompare("Size") == .orderedSame {
              sizeChoices(group)
            } else { optionRows(group) }
          }
        }
      }.padding(16)
    }
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      HStack {
        CaptroBusinessStepper(quantity: quantity, minimum: 1) { quantity = $0 }
        Button {
          add(choices, quantity)
          dismiss()
        } label: {
          Text("Add to Bag · \(captroBusinessPrice(product.price(choices) * quantity))")
        }.buttonStyle(CaptroBusinessPrimary()).disabled(!product.isValid(choices))
          .opacity(product.isValid(choices) ? 1 : 0.45)
      }.padding(.horizontal, 16).padding(.vertical, 8).background(.background)
    }
    .sheet(item: $sheetGroup) { group in
      NavigationStack {
        ScrollView { VStack { optionRows(group) }.padding(16) }
          .navigationTitle(group.name).navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheetGroup = nil } } }
      }.presentationDetents([.medium, .large])
    }
  }

  private func sizeChoices(_ group: CaptroBusinessGroup) -> some View {
    HStack(spacing: 7) {
      ForEach(group.options) { option in
        let selected = choices.contains(option.id)
        Button {
          choices.subtract(group.options.map(\.id))
          if !selected { choices.insert(option.id) }
        } label: {
          VStack(spacing: 1) {
            Text(option.name)
            if option.extra > 0 { Text("+\(captroBusinessPrice(option.extra))").font(.caption2) }
          }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 5).foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.black : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(option.name)
          .accessibilityValue(option.extra > 0 ? captroBusinessPrice(option.extra) + " extra" : "")
          .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }

  private func optionRows(_ group: CaptroBusinessGroup) -> some View {
    ForEach(group.options) { option in
      let selected = choices.contains(option.id)
      Button {
        if selected { choices.remove(option.id) }
        else if group.maximum == 1 {
          choices.subtract(group.options.map(\.id))
          choices.insert(option.id)
        } else if group.options.filter({ choices.contains($0.id) }).count < group.maximum {
          choices.insert(option.id)
        }
      } label: {
        HStack {
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          if let url = option.imageUrl {
            CaptroBusinessPhoto(url: url).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
          }
          Text(option.name)
          Spacer()
          if option.extra > 0 { Text("+\(captroBusinessPrice(option.extra))").foregroundStyle(.secondary) }
        }.frame(minHeight: 44).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
  }
}

func captroBusinessDirections(_ name: String, _ latitude: Double, _ longitude: Double) {
  let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
  item.name = name
  item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
}

func captroBusinessDate(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let parsed = formatter.date(from: value) { return parsed }
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: value)
}
