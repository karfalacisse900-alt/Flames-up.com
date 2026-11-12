import CoreLocation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CaptroBusinessOwner: View {
  let api: MIRAAPIClient
  @State private var shops: [CaptroBusiness] = []
  @State private var error: String?
  @State private var loaded = false

  var body: some View {
    List {
      if !loaded { ProgressView() }
      if let error {
        Text(error)
        Button("Retry") { Task { await load() } }
      }
      ForEach(shops) { shop in
        NavigationLink {
          CaptroBusinessManageShop(api: api, initial: shop)
        } label: {
          VStack(alignment: .leading) {
            Text(shop.name).font(.headline)
            Text(shop.published ? (shop.paused ? "Orders paused" : "Listed") : "Draft · awaiting activation")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      NavigationLink {
        CaptroBusinessShopEditor(api: api, initial: CaptroBusiness()) { saved in shops.append(saved) }
      } label: { Label("Register a business", systemImage: "plus") }
    }
    .navigationTitle("Your Businesses")
    .task { await load() }
    .refreshable { await load() }
  }

  @MainActor private func load() async {
    error = nil
    defer { loaded = true }
    do { shops = try await api.get("/business-owner/shops") }
    catch { self.error = error.localizedDescription }
  }
}

private struct CaptroBusinessManageShop: View {
  let api: MIRAAPIClient
  @State private var shop: CaptroBusiness

  init(api: MIRAAPIClient, initial: CaptroBusiness) {
    self.api = api
    _shop = State(initialValue: initial)
  }

  var body: some View {
    List {
      if !shop.published {
        Text("Draft. Captro must activate this listing and configure checkout before customers can order.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      NavigationLink("Business details") {
        CaptroBusinessShopEditor(api: api, initial: shop) { shop = $0 }
      }
      NavigationLink("Menu and products") { CaptroBusinessMenuEditor(api: api, business: shop) }
      NavigationLink("Orders and pickup") { CaptroBusinessVendorQueue(api: api, business: shop) }
      NavigationLink("Earnings") { CaptroBusinessEarnings(api: api, business: shop) }
    }.navigationTitle(shop.name)
  }
}

private struct CaptroBusinessShopEditor: View {
  private struct Input: Encodable {
    let id, name, category, pickupAddress, hours: String
    let latitude, longitude: Double
    let paused: Bool
    let avatarId: String?
    let photoIds: [String]?
  }

  let api: MIRAAPIClient
  let saved: (CaptroBusiness) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var shop: CaptroBusiness
  @StateObject private var location = CaptroBusinessLocation()
  @State private var latitude: String
  @State private var longitude: String
  @State private var avatar: PhotosPickerItem?
  @State private var photos: [PhotosPickerItem] = []
  @State private var clearPhotos = false
  @State private var clearAvatar = false
  @State private var saving = false
  @State private var error: String?

  init(api: MIRAAPIClient, initial: CaptroBusiness, saved: @escaping (CaptroBusiness) -> Void) {
    self.api = api
    self.saved = saved
    _shop = State(initialValue: initial)
    _latitude = State(initialValue: initial.name.isEmpty ? "" : String(initial.latitude))
    _longitude = State(initialValue: initial.name.isEmpty ? "" : String(initial.longitude))
  }

  var body: some View {
    Form {
      Section("Business") {
        TextField("Name", text: $shop.name)
        Picker("Category", selection: $shop.category) {
          Text("Coffee shop & bakery").tag("coffee_bakery")
          Text("Street food vendor").tag("street_food")
        }
        Toggle("Pause incoming orders", isOn: $shop.paused)
      }
      Section("Pickup") {
        TextField("Pickup address or meeting point", text: $shop.pickupAddress)
        TextField("Latitude", text: $latitude).keyboardType(.numbersAndPunctuation)
        TextField("Longitude", text: $longitude).keyboardType(.numbersAndPunctuation)
        Button("Use current pickup coordinates") { location.request() }
        if location.unavailable { Text("Location is unavailable. You can enter coordinates manually.").font(.footnote) }
        TextField("Hours and pickup notes", text: $shop.hours, axis: .vertical)
        Text("Orders stay open until paused. Keep your hours and pickup location current.").font(.footnote)
      }
      Section("Photos") {
        PhotosPicker(selection: $avatar, matching: .images) {
          Text(avatar == nil ? "Choose profile photo" : "New profile photo selected")
        }.onChange(of: avatar) { _, _ in clearAvatar = false }
        if shop.avatarUrl != nil {
          Toggle("Remove current profile photo", isOn: $clearAvatar)
        }
        PhotosPicker(selection: $photos, maxSelectionCount: 8, matching: .images) {
          Text(photos.isEmpty ? "Replace storefront photos" : "\(photos.count) new photos selected")
        }.onChange(of: photos) { _, _ in clearPhotos = false }
        if !shop.photos.isEmpty { Toggle("Remove current storefront photos", isOn: $clearPhotos) }
      }
      if let error { Text(error).foregroundStyle(.secondary) }
      if saving { ProgressView("Saving business") }
      Button("Save business") { Task { await save() } }.disabled(saving)
    }
    .navigationTitle(shop.name.isEmpty ? "Register Business" : "Edit Business")
    .onReceive(location.$location) { coordinate in
      guard let coordinate else { return }
      latitude = String(coordinate.latitude)
      longitude = String(coordinate.longitude)
    }
    .disabled(saving)
  }

  @MainActor private func save() async {
    guard !saving else { return }
    guard !shop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !shop.pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let lat = Double(latitude), let lon = Double(longitude),
          (-90...90).contains(lat), (-180...180).contains(lon) else {
      error = "Enter a name, pickup address, and valid coordinates."
      return
    }
    saving = true
    error = nil
    defer { saving = false }
    do {
      let uploader = MIRAMediaUploadService(api: api)
      var avatarId: String?
      if clearAvatar { avatarId = "" }
      else if let avatar { avatarId = try await captroBusinessUpload(avatar, uploader: uploader) }
      var photoIds: [String]?
      if clearPhotos { photoIds = [] }
      else if !photos.isEmpty {
        var ids: [String] = []
        for photo in photos { ids.append(try await captroBusinessUpload(photo, uploader: uploader)) }
        photoIds = ids
      }
      let result: CaptroBusiness = try await api.post("/business-owner/shops", body: Input(
        id: shop.id, name: shop.name, category: shop.category, pickupAddress: shop.pickupAddress, hours: shop.hours,
        latitude: lat, longitude: lon, paused: shop.paused, avatarId: avatarId, photoIds: photoIds
      ))
      saved(result)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

private struct CaptroBusinessMenuEditor: View {
  let api: MIRAAPIClient
  let business: CaptroBusiness
  @State private var products: [CaptroBusinessProduct] = []
  @State private var error: String?
  @State private var loading = false
  @State private var more = false

  var body: some View {
    List {
      if loading && products.isEmpty { ProgressView() }
      if let error {
        Text(error)
        Button("Retry") { Task { await load() } }
      }
      ForEach(products) { product in
        NavigationLink {
          CaptroBusinessProductEditor(api: api, business: business, initial: product, saved: apply)
        } label: {
          VStack(alignment: .leading) {
            Text(product.name).font(.headline)
            Text("\(product.category) · \(captroBusinessPrice(product.unitAmount))\(product.available ? "" : " · Unavailable")")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      if more { Button("Load more products") { Task { await load(next: true) } }.disabled(loading) }
      NavigationLink {
        CaptroBusinessProductEditor(api: api, business: business, initial: CaptroBusinessProduct(), saved: apply)
      } label: { Label("Add product", systemImage: "plus") }
    }.navigationTitle("Menu").task { await load() }.refreshable { await load() }
  }

  private func apply(_ product: CaptroBusinessProduct) {
    if let index = products.firstIndex(where: { $0.id == product.id }) { products[index] = product }
    else { products.append(product) }
  }

  @MainActor private func load(next: Bool = false) async {
    guard !loading else { return }
    loading = true
    defer { loading = false }
    error = nil
    do {
      let page: [CaptroBusinessProduct] = try await api.get("/business-owner/\(business.id)/products?offset=\(next ? products.count : 0)")
      if next { page.forEach(apply) } else { products = page }
      more = page.count == 50
    } catch { self.error = error.localizedDescription }
  }
}

private struct CaptroBusinessProductEditor: View {
  private struct Input: Encodable {
    let id, name, category, mode: String
    let unitAmount: Int
    let available: Bool
    let groups: [CaptroBusinessGroup]
    let mediaId: String?
    let optionImageIds: [String: String]
  }

  let api: MIRAAPIClient
  let business: CaptroBusiness
  let saved: (CaptroBusinessProduct) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var product: CaptroBusinessProduct
  @State private var price: String
  @State private var photo: PhotosPickerItem?
  @State private var optionPhotos: [String: PhotosPickerItem] = [:]
  @State private var saving = false
  @State private var error: String?

  init(api: MIRAAPIClient, business: CaptroBusiness, initial: CaptroBusinessProduct, saved: @escaping (CaptroBusinessProduct) -> Void) {
    self.api = api
    self.business = business
    self.saved = saved
    _product = State(initialValue: initial)
    _price = State(initialValue: initial.unitAmount == 0 ? "" : String(initial.unitAmount))
  }

  var body: some View {
    Form {
      Section("Product") {
        TextField("Name", text: $product.name)
        TextField("Menu category", text: $product.category)
        TextField("Price in cents (USD)", text: $price).keyboardType(.numberPad)
        Picker("Ordering mode", selection: $product.mode) {
          Text("Quick add").tag("QUICK_ADD")
          Text("Customize").tag("CUSTOMIZE")
        }
        Toggle("Available", isOn: $product.available)
        PhotosPicker(selection: $photo, matching: .images) { Text(photo == nil ? "Choose product photo" : "New photo selected") }
      }
      if product.isCustom {
        ForEach($product.groups) { $group in
          Section {
            TextField("Group name", text: $group.name)
            Stepper("Minimum: \(group.minimum)", value: $group.minimum, in: 0...30)
            Stepper("Maximum: \(group.maximum)", value: $group.maximum, in: 1...30)
            ForEach($group.options) { $option in
              HStack {
                TextField("Option name", text: $option.name)
                TextField("Extra cents", value: $option.extra, format: .number.grouping(.never))
                  .keyboardType(.numberPad).frame(maxWidth: 88)
              }
              PhotosPicker(selection: Binding(
                get: { optionPhotos[option.id] }, set: { optionPhotos[option.id] = $0 }
              ), matching: .images) {
                Text(optionPhotos[option.id] == nil ? "Choose option photo" : "Option photo selected").font(.footnote)
              }
            }.onDelete { group.options.remove(atOffsets: $0) }
            Button("Add option") { group.options.append(CaptroBusinessOption()) }.disabled(group.options.count >= 30)
            Button("Remove group", role: .destructive) {
              let id = group.id
              product.groups.removeAll { $0.id == id }
            }
          }
        }
        Button("Add option group") { product.groups.append(CaptroBusinessGroup()) }.disabled(product.groups.count >= 12)
      }
      if let error { Text(error).foregroundStyle(.secondary) }
      if saving { ProgressView("Saving product") }
      Button("Save product") { Task { await save() } }.disabled(saving)
    }.navigationTitle("Product").disabled(saving)
  }

  @MainActor private func save() async {
    guard !saving else { return }
    guard let amount = Int(price), (50...100_000).contains(amount) else {
      error = "Enter a USD price of at least 50 cents."
      return
    }
    let groups = product.isCustom ? product.groups : []
    guard !product.isCustom || (!groups.isEmpty && groups.allSatisfy {
      !$0.name.isEmpty && $0.minimum <= $0.maximum && $0.maximum <= $0.options.count && $0.options.allSatisfy {
        !$0.name.isEmpty && (0...5000).contains($0.extra)
      }
    }) else {
      error = "Add valid options and check each group’s selection limits."
      return
    }
    saving = true
    error = nil
    defer { saving = false }
    do {
      let uploader = MIRAMediaUploadService(api: api)
      var imageId: String?
      if let photo { imageId = try await captroBusinessUpload(photo, uploader: uploader) }
      var optionImageIds: [String: String] = [:]
      for option in groups.flatMap(\.options) {
        if let item = optionPhotos[option.id] {
          optionImageIds[option.id] = try await captroBusinessUpload(item, uploader: uploader)
        }
      }
      let result: CaptroBusinessProduct = try await api.post("/business-owner/\(business.id)/products", body: Input(
        id: product.id, name: product.name, category: product.category, mode: product.mode, unitAmount: amount,
        available: product.available, groups: groups, mediaId: imageId, optionImageIds: optionImageIds
      ))
      saved(result)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

private struct CaptroBusinessVendorQueue: View {
  let api: MIRAAPIClient
  let business: CaptroBusiness
  @Environment(\.scenePhase) private var phase
  @State private var orders: [CaptroBusinessOrder] = []
  @State private var error: String?
  @State private var notice: String?
  @State private var scanning = false
  @State private var submitting = false
  @State private var more = false

  var body: some View {
    List {
      Section {
        Button { scanning = true } label: { Label("Scan pickup QR", systemImage: "qrcode.viewfinder") }
          .disabled(submitting)
        if let notice { Text(notice) }
        if let error {
          Text(error).foregroundStyle(.secondary)
          Button("Refresh orders") { Task { await load() } }
        }
      }
      Section("Orders") {
        ForEach(orders) { order in
          NavigationLink { CaptroBusinessOrderDetail(api: api, order: order, vendor: true) } label: {
            VStack(alignment: .leading) {
              Text("#\(order.number) · \(order.statusLabel)").font(.headline)
              Text("\(order.lines.reduce(0) { $0 + $1.quantity }) items · \(captroBusinessPrice(order.total))")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        if more { Button("Load older orders") { Task { await load(next: true) } } }
        if orders.isEmpty && error == nil { Text("No orders yet.").foregroundStyle(.secondary) }
      }
      Section("Payments") {
        Text("Verified totals, fees, and refunds are available on each order. Test orders do not pay out.").font(.footnote)
      }
    }
    .navigationTitle("Orders and Pickup")
    .refreshable { await load() }
    .task(id: phase) {
      guard phase == .active else { return }
      await load()
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(20)) } catch { return }
        if !more || orders.count <= 50 { await load() }
      }
    }
    .sheet(isPresented: $scanning) {
      NavigationStack {
        CaptroQRScanner { code in
          scanning = false
          Task { await submit(code) }
        }.navigationTitle("Scan Pickup QR")
          .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { scanning = false } } }
      }
    }
  }

  @MainActor private func load(next: Bool = false) async {
    do {
      let page: [CaptroBusinessOrder] = try await api.get("/business-owner/\(business.id)/orders?offset=\(next ? orders.count : 0)")
      try Task.checkCancellation()
      orders = next ? orders + page.filter { row in !orders.contains { $0.id == row.id } } : page
      more = page.count == 50
      error = nil
    } catch is CancellationError {
    } catch { self.error = error.localizedDescription }
  }

  @MainActor private func submit(_ code: String) async {
    guard !submitting else { return }
    submitting = true
    error = nil
    notice = nil
    defer { submitting = false }
    do {
      let order: CaptroBusinessOrder = try await api.post("/business-owner/\(business.id)/pickup", body: CaptroBusinessPickup(code: code))
      notice = "Order #\(order.number) picked up."
      await load()
    } catch { self.error = error.localizedDescription }
  }
}

private struct CaptroBusinessEarnings: View {
  struct Totals: Decodable {
    let gross, tax, refunded, processingFee, pendingFees: Int
  }
  let api: MIRAAPIClient
  let business: CaptroBusiness
  @State private var totals: Totals?
  @State private var error: String?

  var body: some View {
    List {
      Section("Stripe test orders") {
        if let totals {
          LabeledContent("Gross received", value: captroBusinessPrice(totals.gross))
          LabeledContent("Tax collected", value: captroBusinessPrice(totals.tax))
          LabeledContent("Confirmed refunds", value: captroBusinessPrice(totals.refunded))
          LabeledContent("Reported Stripe fees", value: captroBusinessPrice(totals.processingFee))
          if totals.pendingFees > 0 { Text("Stripe fees pending for \(totals.pendingFees) orders.").font(.footnote) }
        } else if error == nil { ProgressView() }
        if let error {
          Text(error)
          Button("Retry") { Task { await load() } }
        }
        Text("Stripe sandbox earnings are for testing. Payouts are unavailable.").font(.footnote)
      }
    }.navigationTitle("Business Earnings").task { await load() }.refreshable { await load() }
  }

  @MainActor private func load() async {
    error = nil
    do { totals = try await api.get("/business-owner/\(business.id)/earnings") }
    catch { self.error = error.localizedDescription }
  }
}

private func captroBusinessUpload(_ item: PhotosPickerItem, uploader: MIRAMediaUploadService) async throws -> String {
  guard let type = item.supportedContentTypes.first(where: { $0.preferredMIMEType?.hasPrefix("image/") == true }),
        let mime = type.preferredMIMEType, let data = try await item.loadTransferable(type: Data.self) else {
    throw CaptroBusinessPhotoError.invalid
  }
  let name = UUID().uuidString + "." + (type.preferredFilenameExtension ?? "image")
  let result = try await uploader.uploadResult(MIRAPickedMedia(data: data, kind: .image, fileName: name, mimeType: mime))
  guard let id = result.mediaAssetId else { throw CaptroBusinessPhotoError.invalid }
  return id
}

private enum CaptroBusinessPhotoError: LocalizedError {
  case invalid
  var errorDescription: String? { "Could not upload this photo. Choose another image or try again." }
}
