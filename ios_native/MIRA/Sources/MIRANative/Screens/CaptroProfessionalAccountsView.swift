import SwiftUI
import UIKit

struct CaptroProfessionalAccountsView: View {
  let api: MIRAAPIClient
  @State private var state: CaptroProfessionalState?
  @State private var error: String?
  @State private var loading = false
  @State private var opening = false
  @State private var editing: CaptroProfessionalKind?
  var body: some View {
    List {
      Section {
        Text("Apply separately for Creator / Gig and Business. While your application is reviewed, your regular Captro account stays the same.").font(.subheadline).foregroundStyle(.secondary)
      }
      if let state {
        ForEach(CaptroProfessionalKind.allCases) { kind in
          let application = state.applications.first { $0.role == kind }
          let assigned = state.roles.first { $0.role == kind }
          Section(kind.title) {
            LabeledContent("Status", value: assigned?.statusLabel ?? application?.statusLabel ?? "Not applied")
            if let message = assigned?.statusMessage, !message.isEmpty { Text(message).font(.subheadline) }
            if let message = application?.reviewerMessage, !message.isEmpty { Text(message).font(.subheadline) }
            if assigned == nil {
              if application?.status == "under_review" { Text("We’ll show the review decision here. Submitting does not activate professional features.").font(.footnote).foregroundStyle(.secondary) }
              else { Button(application == nil ? "Apply" : "Edit application") { editing = kind }.accessibilityIdentifier("professional.apply.\(kind.id)") }
            } else if assigned?.status == "active" {
              Button("Edit public information") { editing = kind }
              if kind == .business { NavigationLink("Business management") { CaptroBusinessOwner(api: api) } }
              if kind == .creator { Text("Creator approval is separate from Support readiness. Existing payment and payout requirements still apply.").font(.footnote).foregroundStyle(.secondary) }
            } else if kind == .business {
              NavigationLink("Existing orders & history") { CaptroBusinessOwner(api: api) }
              Text("New ordering and menu changes are unavailable. You can still resolve existing orders.").font(.footnote)
            }
          }
        }
        if state.hasBusinessHistory == true && !state.roles.contains(where: { $0.role == .business }) {
          Section("Existing business") {
            NavigationLink("Existing orders & history") { CaptroBusinessOwner(api: api) }
            Text("Apply for Business to manage new ordering. Existing orders and financial history remain accessible.").font(.footnote).foregroundStyle(.secondary)
          }
        }
        if !state.roles.isEmpty {
          Section("Captro Studio") {
            if state.studioUrl != nil {
              Button(opening ? "Opening…" : "Open Captro Studio") { Task { await openStudio() } }.disabled(opening)
              Text("Manage your professional work on the web using this Captro account.").font(.footnote).foregroundStyle(.secondary)
            } else { Text("Studio is not published yet. Your approval and account are unchanged.").font(.footnote).foregroundStyle(.secondary) }
          }
        }
      }
      if loading && state == nil { ProgressView("Loading applications…") }
      if let error { Section { Text(error); Button("Retry") { Task { await load() } } } }
    }
    .scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
    .navigationTitle("Professional accounts").navigationBarTitleDisplayMode(.inline)
    .task { await load() }.refreshable { await load() }
    .sheet(item: $editing, onDismiss: { Task { await load() } }) { kind in
      CaptroProfessionalApplicationForm(api: api, kind: kind,
        record: state?.roles.first { $0.role == kind } ?? state?.applications.first { $0.role == kind },
        isApproved: state?.roles.contains { $0.role == kind && $0.status == "active" } == true)
    }
  }
  private func load() async {
    guard !loading else { return }; loading = true; defer { loading = false }
    let scope = api.presentationScope
    do { let result: CaptroProfessionalState = try await api.get("/professional/me")
      guard !Task.isCancelled, scope == api.presentationScope else { state = nil; return }; state = result; error = nil
    } catch { self.error = "Couldn’t load applications. Pull to refresh or try again." }
  }
  private struct Empty: Encodable {}
  private struct Handoff: Decodable { let url: String }
  private func openStudio() async {
    guard !opening else { return }; opening = true; defer { opening = false }
    do {
      let handoff: Handoff = try await api.post("/professional/studio-handoff", body: Empty())
      guard let url = URL(string: handoff.url), url.scheme == "https", url.user == nil, url.password == nil,
        url.host == URL(string: state?.studioUrl ?? "")?.host else { throw URLError(.badURL) }
      if !((await UIApplication.shared.open(url))) { error = "Couldn’t open Studio in your browser." }
    } catch { self.error = "Couldn’t open Studio. Retry from Settings; your account is unchanged." }
  }
}

struct CaptroProfessionalApplicationForm: View {
  let api: MIRAAPIClient
  let kind: CaptroProfessionalKind
  let record: CaptroProfessionalRecord?
  let isApproved: Bool
  @Environment(\.dismiss) private var dismiss
  @State private var data: CaptroProfessionalData
  @State private var links: String
  @State private var message: String
  @State private var busy = false
  @State private var error: String?
  @State private var operationID = UUID().uuidString
  init(api: MIRAAPIClient, kind: CaptroProfessionalKind, record: CaptroProfessionalRecord?, isApproved: Bool) {
    self.api = api; self.kind = kind; self.record = record; self.isApproved = isApproved
    let data = record?.publicData ?? CaptroProfessionalData(category: kind.categories[0])
    _data = State(initialValue: data); _links = State(initialValue: data.links.joined(separator: "\n"))
    _message = State(initialValue: record?.applicantMessage ?? "")
  }
  private var submittedData: CaptroProfessionalData {
    var result = data; result.links = links.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; return result
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Public display name", text: $data.displayName).textContentType(.name).accessibilityIdentifier("professional.name")
          Picker("Category", selection: $data.category) { ForEach(kind.categories, id: \.self) { Text(CaptroProfessionalKind.label($0)).tag($0) } }
          TextField("What do you do?", text: $data.description, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("professional.description")
          TextField("HTTPS links, one per line (optional)", text: $links, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
          if kind == .business {
            Toggle("Offers pickup", isOn: $data.pickup)
            TextField("City or operating area", text: $data.area)
          }
        } header: { Text("Public after approval") } footer: { Text("Name, category, description, links and operating area appear on your professional profile. A website is optional. Up to three HTTPS links.") }
        if !isApproved {
          Section { TextField("Anything reviewers should know? (optional)", text: $message, axis: .vertical).lineLimit(3...6) }
            header: { Text("Only reviewers can see this") }
            footer: { Text("Do not include bank details, government IDs or other sensitive documents.") }
        }
        if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("professional.error") }
        Section {
          if !isApproved { Button("Save draft") { Task { await save("save") } }.disabled(busy) }
          Button(isApproved ? "Save changes" : "Submit for review") { Task { await save(isApproved ? "edit_public" : "submit") } }
            .disabled(busy || !submittedData.valid(for: kind)).accessibilityIdentifier("professional.submit")
          if busy { ProgressView("Saving…") }
        }
      }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        .interactiveDismissDisabled(busy)
    }
    .onChange(of: data) { _, _ in operationID = UUID().uuidString }
    .onChange(of: links) { _, _ in operationID = UUID().uuidString }
    .onChange(of: message) { _, _ in operationID = UUID().uuidString }
  }
  private struct Payload: Encodable { let id: String; let version: Int; let `public`: CaptroProfessionalData; let message: String }
  private struct Response: Decodable { let ok: Bool }
  private func save(_ action: String) async {
    guard !busy else { return }; busy = true; defer { busy = false }; let scope = api.presentationScope
    do {
      let result: Response = try await api.post("/professional/\(kind.id)/\(action)", body: Payload(id: operationID, version: record?.version ?? 0, public: submittedData, message: message))
      guard scope == api.presentationScope, !Task.isCancelled else { return }
      if result.ok { dismiss() }
    } catch { self.error = error.localizedDescription }
  }
}

struct CaptroProfessionalProfileInfo: View {
  let roles: [CaptroProfessionalPublicRole]
  let api: MIRAAPIClient
  var body: some View {
    ForEach(roles) { role in
      VStack(alignment: .leading, spacing: 6) {
        Text(CaptroProfessionalKind.label(role.category)).font(.subheadline.weight(.medium))
        if !role.description.isEmpty { Text(role.description).font(.subheadline) }
        if role.role == "business", !role.area.isEmpty { Text(role.area).font(.caption).foregroundStyle(.secondary) }
        ForEach(role.links, id: \.self) { raw in
          if let url = URL(string: raw), url.scheme == "https", let host = url.host {
            Link(host, destination: url).font(.subheadline).frame(minHeight: 44).accessibilityLabel("Open \(host)")
          }
        }
        if role.role == "business" {
          ForEach(role.shops ?? []) { shop in
            NavigationLink("Menu · \(shop.name)") { CaptroProfessionalMenuDestination(api: api, id: shop.id) }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
          }
        }
      }
    }
  }
}
struct CaptroProfessionalProfileHeader: View {
  let user: MIRAUser?
  let api: MIRAAPIClient
  @Binding var selection: String
  var posts: [MIRAPost] = []
  private var roles: [CaptroProfessionalPublicRole] {
    guard user?.privacyLocked != true, user?.viewerHasBlocked != true, user?.viewerBlockedBy != true else { return [] }
    return user?.professional ?? []
  }
  var body: some View {
    let chosen = roles.first { $0.role == selection } ?? roles.first
    VStack(alignment: .leading, spacing: 12) {
      if roles.count > 1 {
        Picker("Profile", selection: $selection) {
          ForEach(roles) { Text($0.role == "creator" ? "Creator / Gig" : "Business").tag($0.role) }
        }.pickerStyle(.segmented).accessibilityIdentifier("professional.profile.switch")
      }
      CaptroProfileIntroduction(user: user, professionalRole: chosen)
      if let chosen { CaptroProfessionalProfileInfo(roles: [chosen], api: api) }
      if chosen?.role == "creator", let gig = posts.first(where: { post in
        post.isProfilePlan && (CaptroStoryExpiry.date(post.detail?.commerce?.startsAt ?? post.detail?.event?.startsAt) ?? .distantPast) > Date()
      }) {
        NavigationLink { DiscoverPostDetailNativeView(post: gig, api: api) } label: {
          CaptroProfileItemRow(post: gig)
        }.buttonStyle(.plain).accessibilityLabel("View upcoming plan")
      }
    }.onChange(of: roles.map(\.role), initial: true) { _, values in
      if !values.contains(selection), let first = values.first { selection = first }
    }
  }
}
private struct CaptroProfessionalMenuDestination: View {
  let api: MIRAAPIClient; let id: String
  @State private var business: CaptroBusiness?
  @State private var error: String?
  @State private var retry = 0
  
  var body: some View {
    Group {
      if let business { CaptroBusinessStorefront(api: api, business: business, isGuest: false) }
      else if let error { VStack { Text(error); Button("Retry") { retry += 1 } } }
      else { ProgressView("Loading menu…") }
    }.task(id: retry) {
      let scope = api.presentationScope
      do { let result: CaptroBusiness = try await api.get("/businesses/\(id)"); guard scope == api.presentationScope, !Task.isCancelled else { return }; business = result }
      catch { self.error = "This menu is unavailable. Try again later." }
    }
  }
}
