import SwiftUI
import UIKit

enum CaptroTeaNoteDestination: Hashable {
  case listing(CaptroTeaEntry)
  case profile(String)
}

struct CaptroTeaNoteDestinationView: View {
  let destination: CaptroTeaNoteDestination
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  var body: some View {
    switch destination {
    case .profile(let id): UserProfileNativeView(userId: id, api: api).toolbar(.visible, for: .navigationBar)
    case .listing(let entry):
      if entry.destination.source == "post", let post = entry.post { DiscoverPostDetailNativeView(post: post, api: api) }
      else if entry.kind == "club" { CaptroTeaClubDestination(entry: entry, api: api, viewerID: viewerID, signIn: signIn) }
      else { CaptroTeaDetailView(entry: entry, api: api, viewerID: viewerID, signIn: signIn) }
    }
  }
}

/// Shared by a Note row and its details. A button never opens the enclosing row.
@MainActor struct CaptroTeaNoteActionView: View {
  let note: CaptroTeaConversation
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  var coverChanged: (Bool) -> Void = { _ in }
  let navigate: (CaptroTeaNoteDestination) -> Void
  @State private var busy = false
  @State private var error: String?
  @State private var form: CaptroTeaConversation?
  @State private var applications = false
  @State private var checkedState: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let action = note.primaryAction {
        Button { Task { await open() } } label: {
          HStack(spacing: 6) {
            Text(note.applicationSubmitted == true && action.kind == "application" ? "Application submitted" : checkedState ?? action.statusLabel)
              .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if busy { ProgressView().controlSize(.small) }
            else { Image(systemName: action.kind == "external" ? "arrow.up.right" : "chevron.right").font(.caption) }
          }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(CaptroTeaStyle.accent).disabled(busy)
          .accessibilityIdentifier("tea.note.action." + note.id)
          .accessibilityLabel((note.applicationSubmitted == true ? "Application submitted" : action.statusLabel) + (action.url.flatMap(CaptroTeaLink.init).map { ", " + $0.hostname } ?? ""))
        if let link = action.url.flatMap(CaptroTeaLink.init) { Text(link.hostname).font(.caption).foregroundStyle(.secondary) }
      }
      if note.canManageApplications == true {
        Button("View applications") { applications = true }.font(.subheadline).frame(minHeight: 44)
          .accessibilityIdentifier("tea.note.applications")
      }
      if let error { Text(error).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
    .sheet(item: $form) { note in CaptroTeaApplicationView(note: note, api: api) }
    .sheet(isPresented: $applications) { CaptroTeaApplicationsView(note: note, api: api) }
    .onChange(of: form != nil || applications) { _, covered in coverChanged(covered) }
    .onChange(of: note.primaryAction) { _, _ in checkedState = nil }
  }
  private func open() async {
    guard !busy else { return }
    if note.primaryAction?.kind == "application", viewerID == nil { signIn(); return }
    busy = true; error = nil; defer { busy = false }
    let scope = api.presentationScope
    do {
      let result: CaptroTeaNoteActionResolution = try await api.getFresh("/tea/conversations/" + note.id + "/action")
      guard scope == api.presentationScope, result.note.id == note.id, !Task.isCancelled else { return }
      api.teaConversations.model(for: result.note).updated(result.note)
      guard let action = result.note.primaryAction else { checkedState = "Unavailable"; return }
      // Reopening a confirmed receipt is safe even after admission has closed.
      if action.kind == "application", result.note.applicationSubmitted == true { form = result.note; return }
      guard action.state == "active" else { checkedState = action.statusLabel; return }
      switch action.kind {
      case "application":
        if result.note.isAuthor { applications = true } else { form = result.note }
      case "listing":
        guard let entry = result.listing else { checkedState = "Unavailable"; return }
        navigate(.listing(entry))
      case "external":
        guard let link = action.url.flatMap(CaptroTeaLink.init) else { checkedState = "Unavailable"; return }
        if let destination = link.profile { navigate(.profile(destination.id)) }
        else { UIApplication.shared.open(link.url, options: [:]) { success in
          if !success { Task { @MainActor in if scope == api.presentationScope { error = "Couldn’t open this website. Try again." } } }
        } }
      default: checkedState = "Unavailable"
      }
    } catch {
      guard scope == api.presentationScope else { return }
      self.error = CaptroRefreshFailure.message(error, content: "this action", cached: false)
    }
  }
}

@MainActor struct CaptroTeaNoteActionEditor: View {
  let api: MIRAAPIClient
  let save: (CaptroTeaNoteAction?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var action: CaptroTeaNoteAction
  @State private var allowedForms = false
  @State private var capabilityError: String?
  @State private var chosenListing: String?
  private let existingForm: Bool
  init(api: MIRAAPIClient, action: CaptroTeaNoteAction?, save: @escaping (CaptroTeaNoteAction?) -> Void) {
    self.api = api; self.save = save; existingForm = action?.kind == "application"
    _action = State(initialValue: action?.input ?? CaptroTeaNoteAction(kind: "external", label: "Open link", url: ""))
  }
  var body: some View {
    NavigationStack {
      Form {
        actionSection
        if !allowedForms {
          Section { Text(capabilityError ?? "Native application forms require an approved, active Creator or Business account. You can link to your own HTTPS form.").font(.footnote).foregroundStyle(.secondary) }
        }
        previewSection
        Button("Remove action", role: .destructive) { save(nil); dismiss() }
      }.scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
        .navigationTitle("Note action").navigationBarTitleDisplayMode(.inline).miraNavigationSurface().tint(CaptroTeaStyle.accent)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) { Button("Done") { save(action.input); dismiss() }.disabled(!action.valid).accessibilityIdentifier("tea.action.done") }
        }
        .onChange(of: action.kind) { _, kind in changeKind(kind) }
        .task { await loadCapabilities() }
    }
  }
  private var actionSection: some View {
    Section("Action") {
          Picker("Type", selection: $action.kind) {
            Text("External link").tag("external")
            Text("Captro listing").tag("listing")
            if allowedForms || existingForm { Text("Application form").tag("application") }
          }.accessibilityIdentifier("tea.action.kind")
          TextField("Button label", text: $action.label).accessibilityIdentifier("tea.action.label")
          if action.kind == "external" {
            TextField("https://", text: Binding(get: { action.url ?? "" }, set: { action.url = $0 }))
              .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("tea.action.url")
          } else if action.kind == "listing" {
            NavigationLink(chosenListing ?? (action.listingId == nil ? "Choose existing listing" : "Change linked listing")) {
              CaptroTeaNoteListingPicker(api: api) { entry in action.listingId = entry.destination.id; action.listingSource = entry.destination.source; chosenListing = entry.name }
            }.accessibilityIdentifier("tea.action.listing")
            Text("Links to the original listing and its existing access, claim, or checkout flow.").font(.footnote).foregroundStyle(.secondary)
          } else {
            Toggle("Ask for height (optional)", isOn: Binding(get: { action.heightRequested ?? false }, set: { action.heightRequested = $0 })).disabled(!allowedForms)
            Toggle("Accepting applications", isOn: Binding(get: { action.accepting ?? true }, set: { action.accepting = $0 }))
            Text("Full name, availability, and optional portfolio link. Applications are private and only you can read them.").font(.footnote).foregroundStyle(.secondary)
          }
    }
  }
  private var previewSection: some View {
    Section("Preview") {
          Text(action.label.isEmpty ? "Add a short button label" : action.label).font(.subheadline.weight(.semibold)).foregroundStyle(CaptroTeaStyle.accent)
          if let link = action.url.flatMap(CaptroTeaLink.init), action.kind == "external" { Text(link.hostname).font(.caption).foregroundStyle(.secondary) }
          if let chosenListing, action.kind == "listing" { Text(chosenListing).font(.caption) }
    }
  }
  private func changeKind(_ kind: String) {
    let label: String
    switch kind {
    case "application": label = "Apply"
    case "listing": label = "View listing"
    default: label = "Open link"
    }
    action = CaptroTeaNoteAction(kind: kind, label: label,
      url: kind == "external" ? "" : nil,
      heightRequested: kind == "application" ? false : nil,
      accepting: kind == "application" ? true : nil)
  }
  private func loadCapabilities() async {
    struct Capabilities: Decodable { let canCreateForms: Bool }
    let scope = api.presentationScope
    do {
      let result: Capabilities = try await api.getFresh("/tea/conversations/capabilities")
      guard scope == api.presentationScope, !Task.isCancelled else { return }
      allowedForms = result.canCreateForms
    } catch {
      guard scope == api.presentationScope, !Task.isCancelled else { return }
      capabilityError = "Couldn’t check form creation access. Reopen Add action to retry. External links and listings remain available."
    }
  }
}

@MainActor private struct CaptroTeaNoteListingPicker: View {
  let api: MIRAAPIClient
  let choose: (CaptroTeaEntry) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var items: [CaptroTeaEntry] = []
  @State private var cursor: String?
  @State private var loaded = false
  @State private var loading = false
  @State private var error: String?
  var body: some View {
    List {
      ForEach(items) { entry in Button { choose(entry); dismiss() } label: {
        VStack(alignment: .leading, spacing: 4) { Text(entry.name); Text(entry.typeLabel).font(.caption).foregroundStyle(.secondary) }
      }.buttonStyle(.plain) }
      if loading { ProgressView("Loading listings…") }
      if loaded && items.isEmpty { Text("No eligible listings found.").foregroundStyle(.secondary) }
      if let error { Text(error).font(.footnote); Button("Retry") { Task { await load() } } }
      else if cursor != nil { Button("Load more") { Task { await load() } }.disabled(loading) }
    }.navigationTitle("Link a listing").navigationBarTitleDisplayMode(.inline)
      .task { if !loaded { await load() } }
  }
  private func load() async {
    guard !loading else { return }; loading = true; error = nil; defer { loading = false }
    let scope = api.presentationScope
    do {
      var path = URLComponents(string: "/tea")!
      path.queryItems = [URLQueryItem(name: "include_posts", value: "1")]
      if let cursor { path.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
      let page: CaptroTeaPage = try await api.getFresh(path.string!)
      guard scope == api.presentationScope, !Task.isCancelled else { return }
      var seen = Set(items.map(\.id))
      items += page.items.filter { ["activity","post"].contains($0.destination.source) && seen.insert($0.id).inserted }
      cursor = page.nextCursor; loaded = true
    } catch { if scope == api.presentationScope { self.error = "Couldn’t load listings. Try again." } }
  }
}

@MainActor struct CaptroTeaApplicationView: View {
  @StateObject private var model: CaptroTeaApplicationModel
  @Environment(\.dismiss) private var dismiss
  init(note: CaptroTeaConversation, api: MIRAAPIClient) { _model = StateObject(wrappedValue: api.teaConversations.application(for: note)) }
  var body: some View {
    NavigationStack {
      Form {
        if model.validScope {
          Section {
            HStack(spacing: 10) {
              CaptroTeaIdentity(name: model.note.author.name, photo: model.note.author.photoURL)
              VStack(alignment: .leading) { Text(model.note.author.name).font(.headline); Text(model.note.title).font(.subheadline) }
            }
          } footer: { Text("Your application is sent privately to \(model.note.author.name). It will not appear in Notes or replies.") }
          if model.confirmed {
            Label("Application submitted", systemImage: "checkmark.circle").accessibilityIdentifier("tea.application.confirmed")
          } else {
            Section {
              TextField("Full name", text: $model.fullName).textContentType(.name).accessibilityIdentifier("tea.application.name")
              if model.note.primaryAction?.heightRequested == true { TextField("Height (optional, include units)", text: $model.height).accessibilityIdentifier("tea.application.height") }
              TextField("Availability", text: $model.availability, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("tea.application.availability")
              TextField("Portfolio link (optional)", text: $model.portfolio).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }.disabled(model.busy || model.pending != nil)
            if let error = model.error { Text(error).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("tea.application.error") }
            Button(model.busy ? "Submitting…" : model.pending != nil ? "Retry submission" : "Submit") { Task { await model.submit() } }
              .disabled(model.busy || (model.pending == nil && !model.validFields)).accessibilityIdentifier("tea.application.submit")
          }
        } else { Text("Sign in again to open this application.") }
      }.scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
        .navigationTitle("Application").navigationBarTitleDisplayMode(.inline).miraNavigationSurface()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .tint(CaptroTeaStyle.accent)
    }
  }
}

@MainActor struct CaptroTeaApplicationsView: View {
  let note: CaptroTeaConversation
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var rows: [CaptroTeaApplication] = []
  @State private var cursor: String?
  @State private var loading = false
  @State private var loaded = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      List {
        if loading && !loaded { ProgressView("Loading applications…") }
        if loaded && rows.isEmpty { Text("No applications yet.").foregroundStyle(.secondary) }
        ForEach(rows) { row in
          VStack(alignment: .leading, spacing: 6) {
            Text(row.answers.fullName).font(.headline)
            TeaConversationTime(value: row.createdAt)
            if let height = row.answers.height { Text("Height: " + height).font(.subheadline) }
            Text(row.answers.availability).font(.body)
            if let link = row.answers.portfolio.flatMap(CaptroTeaLink.init) { Link(link.hostname, destination: link.url).font(.subheadline).frame(minHeight: 44) }
          }
        }
        if let error { Text(error).font(.footnote); Button("Retry") { Task { await load(reset: !loaded) } } }
        else if cursor != nil { Button("Load more") { Task { await load(reset: false) } }.disabled(loading) }
      }.scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
        .navigationTitle("Applications").navigationBarTitleDisplayMode(.inline).miraNavigationSurface()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await load(reset: true) }.refreshable { await load(reset: true) }
        .onReceive(NotificationCenter.default.publisher(for: .captroTeaAccessChanged)) { _ in rows = []; loaded = false; cursor = nil; dismiss() }
    }
  }
  private func load(reset: Bool) async {
    guard !loading else { return }; loading = true; error = nil; defer { loading = false }
    let scope = api.presentationScope
    do {
      var path = URLComponents(string: "/tea/conversations/" + note.id + "/applications")!
      if !reset, let cursor { path.queryItems = [URLQueryItem(name: "cursor", value: cursor)] }
      let result: CaptroTeaConversationPage<CaptroTeaApplication> = try await api.getFresh(path.string!)
      guard scope == api.presentationScope, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : rows.map(\.id))
      rows = (reset ? [] : rows) + result.items.filter { seen.insert($0.id).inserted }
      cursor = result.nextCursor; loaded = true
    } catch {
      guard scope == api.presentationScope else { return }
      if case MIRAAPIError.server(let status, _, _) = error, [401,403,404].contains(status) { rows = []; loaded = false; cursor = nil }
      self.error = CaptroRefreshFailure.message(error, content: "applications", cached: !rows.isEmpty)
    }
  }
}
