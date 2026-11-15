import SwiftUI
import UIKit

struct CaptroClubLinkDraft: Identifiable {
  let id: String
  var title, url: String
  let message: String?
  let version: Int?
  init(url: String = "", message: String? = nil) {
    id = UUID().uuidString; title = ""; self.url = url; self.message = message; version = nil
  }
  init(saved: CaptroClubLink) { id = saved.id; title = saved.title; url = saved.url; message = saved.messageId; version = saved.version }
}
struct CaptroClubLinkEditor: View {
  @ObservedObject var model: CaptroTeaClubModel
  @State var draft: CaptroClubLinkDraft
  @State private var saving = false
  @State private var submitted: CaptroClubAction?
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $draft.title).accessibilityIdentifier("tea.club.link-name")
        TextField("https://", text: $draft.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("tea.club.link-url")
        if let error { Text(error).font(.footnote) }
      }.disabled(saving || submitted != nil).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
        .navigationTitle(draft.version == nil ? "Add link" : "Edit link").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
          ToolbarItem(placement: .confirmationAction) { Button(submitted == nil ? "Save" : "Retry") { Task { await save() } }.disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.title.count > 100 || CaptroTeaLink(draft.url) == nil).accessibilityIdentifier("tea.club.link-save") }
        }.interactiveDismissDisabled(saving)
    }
  }
  private func save() async {
    guard !saving else { return }; saving = true; error = nil; defer { saving = false }
    let payload = submitted ?? CaptroClubAction(id: draft.id, message: draft.version == nil ? draft.message : nil, title: draft.title, url: draft.url, version: draft.version)
    submitted = payload
    do { try await model.perform(draft.version == nil ? "saveLink" : "editLink", payload); dismiss() }
    catch {
      if case MIRAAPIError.server(let status, _, _) = error, [400,403,404,409].contains(status) { submitted = nil }
      self.error = "Couldn’t confirm this change. Retry checks the same link."
    }
  }
}

@MainActor struct CaptroTeaClubManagement: View {
  @ObservedObject var model: CaptroTeaClubModel
  let api: MIRAAPIClient
  let section: String
  let mention: (CaptroClubMember) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var members: [CaptroClubMember] = []
  @State private var invites: [CaptroClubInvite] = []
  @State private var requests: [CaptroClubInviteRequest] = []
  @State private var cursor: String?
  @State private var requestCursor: String?
  @State private var loading = false
  @State private var loaded = false
  @State private var busy = false
  @State private var error: String?
  @State private var roomName = ""
  @FocusState private var roomFieldFocused: Bool
  @State private var announcements = false
  @State private var newRoomID = UUID().uuidString
  @State private var newInviteID = UUID().uuidString
  @State private var submittedInvite: CaptroClubAction?
  @State private var submittedRoom: CaptroClubAction?
  @State private var approval = true
  @State private var expiryDays = 7
  @State private var rules = ""
  @State private var officialLinks = ""
  @State private var confirm: ClubMemberChange?

  var body: some View {
    NavigationStack {
      List {
        if model.club == nil || !model.valid { Text("Club access is no longer available.") }
        else {
          switch section {
          case "Rooms": rooms
          case "Invites": invitations
          case "Club settings": settings
          default: roster
          }
          if loading { ProgressView("Loading") }
          if let error { Text(error).font(.footnote).foregroundStyle(.secondary); Button("Retry") { Task { await load() } } }
        }
      }.listStyle(.plain).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
        .navigationTitle(section).navigationBarTitleDisplayMode(.inline).miraNavigationSurface()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
          approval = model.club?.approvalRequired ?? true; rules = model.club?.rules ?? ""; officialLinks = model.club?.officialLinks.joined(separator: "\n") ?? ""
          await load()
        }
        .confirmationDialog("Change member access?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { change in
          Button(change.title, role: change.action == "removeMember" ? .destructive : nil) { Task { await mutate(change.action, .init(user: change.user, role: change.role)); confirm = nil; await load() } }
        } message: { change in Text(change.name + " · " + change.title) }
    }
  }
  private var rooms: some View {
    Group {
      Button { model.room = nil; model.tab = "Chat"; dismiss() } label: { roomLabel("General", selected: model.room == nil, unread: model.club?.generalUnread == true) }.accessibilityIdentifier("tea.room.general")
      ForEach(model.club?.rooms ?? []) { room in
        Button { model.room = room.id; model.tab = "Chat"; dismiss() } label: {
          VStack(alignment: .leading, spacing: 4) {
            roomLabel(room.name, selected: model.room == room.id, unread: room.unread == true)
            if room.announcements { Text("Announcements · organizers can post").font(.caption).foregroundStyle(.secondary) }
          }
        }.accessibilityIdentifier("tea.room." + room.id)
      }
      if model.club?.canManage == true {
        Section("Add a room") {
          TextField("Room name", text: $roomName).focused($roomFieldFocused).submitLabel(.done).onSubmit { roomFieldFocused = false }
            .accessibilityIdentifier("tea.room.name").disabled(submittedRoom != nil)
          Toggle("Only organizers can post", isOn: $announcements).disabled(submittedRoom != nil)
          Button(submittedRoom == nil ? "Create room" : "Retry room creation") {
            Task {
              let payload = submittedRoom ?? CaptroClubAction(id: newRoomID, name: roomName, announcements: announcements)
              submittedRoom = payload
              if await mutate("createRoom", payload) { roomName = ""; newRoomID = UUID().uuidString; submittedRoom = nil }
            }
          }.disabled(busy || roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomName.count > 60).accessibilityIdentifier("tea.room.create")
        }
      }
    }
  }
  private func roomLabel(_ name: String, selected: Bool, unread: Bool) -> some View {
    HStack {
      Text(name); Spacer()
      if unread { Text("Unread").font(.caption).foregroundStyle(.secondary) }
      if selected { Image(systemName: "checkmark").accessibilityLabel("Selected") }
    }.frame(minHeight: 44).contentShape(Rectangle())
  }
  private var invitations: some View {
    Group {
      if model.club?.canManage == true {
        Section("Create invitation") {
          Picker("Expires after", selection: $expiryDays) { Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30) }.disabled(submittedInvite != nil)
          Toggle("Require organizer approval", isOn: $approval).disabled(model.club?.approvalRequired == true || submittedInvite != nil)
          Text("Invitations keep the club’s existing admission and payment requirements.").font(.footnote).foregroundStyle(.secondary)
          Button(submittedInvite == nil ? "Create invite link" : "Retry invite creation") {
            Task {
              let payload = submittedInvite ?? CaptroClubAction(id: newInviteID, expires: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(expiryDays * 86400) - 30)), approval: approval)
              submittedInvite = payload
              if await mutate("createInvite", payload) { newInviteID = UUID().uuidString; submittedInvite = nil; await load() }
            }
          }.disabled(busy).accessibilityIdentifier("tea.invite.create")
        }
        Section("Invite links") {
          if loaded && invites.isEmpty { Text("No invite links yet.").foregroundStyle(.secondary) }
          ForEach(invites) { invite in
            VStack(alignment: .leading, spacing: 6) {
              Text(invite.revokedAt != nil ? "Revoked" : invite.active ? "Active invitation" : "Expired").font(.subheadline.weight(.semibold))
              if let date = captroTeaDate(invite.expiresAt) { Text("Expires " + date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
              if invite.requiresApproval { Text("Organizer approval required").font(.caption) }
              if invite.active {
                if let raw = invite.url, let url = URL(string: raw) {
                  HStack {
                    ShareLink("Share invite", item: url).frame(minHeight: 44)
                    Button("Copy link") { UIPasteboard.general.url = url; UIAccessibility.post(notification: .announcement, argument: "Invite link copied") }.frame(minHeight: 44)
                  }
                } else { Text("Create a new link; this link can no longer be copied.").font(.footnote) }
                Button("Revoke invite", role: .destructive) { Task { if await mutate("revokeInvite", .init(id: invite.id)) { await load() } } }.disabled(busy).frame(minHeight: 44)
              }
            }
          }
          if cursor != nil { Button("More invitations") { Task { await load(more: true) } } }
        }
        Section("Admission requests") {
          if loaded && requests.isEmpty { Text("No pending requests.").foregroundStyle(.secondary) }
          ForEach(requests) { request in
            VStack(alignment: .leading) {
              Text(request.name)
              HStack {
                Button("Approve") { decide(request, approve: true) }.frame(minHeight: 44)
                Button("Decline", role: .destructive) { decide(request, approve: false) }.frame(minHeight: 44)
              }.buttonStyle(.borderless).disabled(busy)
            }
          }
          if requestCursor != nil { Button("More requests") { Task { await loadRequests(more: true) } } }
        }
      } else { Text("Only organizers can manage invitations.") }
    }
  }
  private var settings: some View {
    Group {
      if let club = model.club, club.canManage {
        TextField("Rules", text: $rules, axis: .vertical).lineLimit(4...12)
        TextField("Official HTTPS links, one per line", text: $officialLinks, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).lineLimit(3...6)
        Button("Save") {
          Task {
            let links = officialLinks.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard links.count <= 3, links.allSatisfy({ CaptroTeaLink($0) != nil }), rules.count <= 8000 else { error = "Use up to three valid HTTPS links and at most 8,000 characters for rules."; return }
            if await mutate("settings", .init(version: club.version, rules: rules, links: links)) { dismiss() }
          }
        }.disabled(busy)
      }
    }
  }
  private var roster: some View {
    Group {
      ForEach(members) { member in
        HStack {
          VStack(alignment: .leading) { Text(member.name); Text("@" + member.username + " · " + member.role).font(.caption).foregroundStyle(.secondary) }
          Spacer()
          if section == "Mention a member" {
            Button("Mention") { mention(member) }.frame(minHeight: 44)
          } else if model.club?.canManage == true, member.role != "owner" {
            Menu {
              if model.club?.role == "owner" { Button(member.role == "admin" ? "Make member" : "Make organizer") { confirm = .init(action: "memberRole", user: member.id, role: member.role == "admin" ? "member" : "admin", name: member.name, title: member.role == "admin" ? "Make member" : "Make organizer") } }
              if model.club?.role == "owner" || member.role != "admin" { Button("Remove from club", role: .destructive) { confirm = .init(action: "removeMember", user: member.id, role: nil, name: member.name, title: "Remove from club") } }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Manage " + member.name)
          }
        }
      }
      if cursor != nil { Button("More members") { Task { await load(more: true) } } }
      if loaded && members.isEmpty { Text("No members to display.") }
    }
  }
  private func decide(_ request: CaptroClubInviteRequest, approve: Bool) {
    Task { if await mutate("decideInvite", .init(id: request.inviteId, user: request.userId, approve: approve)) { await loadRequests() } }
  }
  @discardableResult private func mutate(_ action: String, _ payload: CaptroClubAction) async -> Bool {
    guard !busy else { return false }; busy = true; error = nil; defer { busy = false }
    do { try await model.perform(action, payload); return true }
    catch {
      if case MIRAAPIError.server(let status, _, let detail) = error, [400,403,404,409].contains(status) {
        if action == "createRoom" { submittedRoom = nil }
        if action == "createInvite" { submittedInvite = nil }
        self.error = detail ?? "This change was rejected. Check the details and try again."
        if status == 409 { await model.load(force: true) }
      } else { self.error = "Couldn’t confirm the change. Retry checks the same request." }
      return false
    }
  }
  private func load(more: Bool = false) async {
    guard !loading, model.valid else { return }; loading = true; error = nil; defer { loading = false }
    do {
      switch section {
      case "Invites":
        let page: CaptroTeaConversationPage<CaptroClubInvite> = try await api.getFresh(model.base + "/invites" + (more ? "?cursor=" + (cursor ?? "") : ""))
        guard model.valid, !Task.isCancelled else { return }; invites = (more ? invites : []) + page.items; cursor = page.nextCursor
        if !more { await loadRequests() }
      case "Members", "Mention a member":
        let page: CaptroTeaConversationPage<CaptroClubMember> = try await api.getFresh(model.base + "/members" + (more ? "?after=" + (cursor ?? "") : ""))
        guard model.valid, !Task.isCancelled else { return }; members = (more ? members : []) + page.items; cursor = page.nextCursor
      default: break
      }
      loaded = true
    } catch { self.error = "Couldn’t load this section. Try again." }
  }
  private func loadRequests(more: Bool = false) async {
    do {
      let page: CaptroTeaConversationPage<CaptroClubInviteRequest> = try await api.getFresh(model.base + "/inviteRequests" + (more ? "?cursor=" + (requestCursor ?? "") : ""))
      guard model.valid else { return }; requests = (more ? requests : []) + page.items; requestCursor = page.nextCursor
    } catch { self.error = "Couldn’t load admission requests. Try again." }
  }
}
private struct ClubMemberChange { let action, user: String; let role: String?; let name, title: String }

struct CaptroTeaInviteView: View {
  let token: String
  let api: MIRAAPIClient
  let signedIn: Bool
  @State private var invitation: CaptroClubInvitation?
  @State private var error: String?
  @State private var loading = false
  @State private var destination = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !signedIn { Text("Sign in to Captro, then reopen this invitation. No account has been switched.") }
      else if let invitation {
        Text(invitation.name).font(.title3.bold())
        switch invitation.state {
        case "member": Text("You’re already a member."); Button("Open club") { destination = true }
        case "approval_required": Text("An organizer must approve this invitation."); Button("Request admission") { Task { await load(accept: true) } }.disabled(loading)
        case "pending": Text("Waiting for organizer approval."); Button("Check status") { Task { await load() } }
        case "denied": Text("This admission request was declined.")
        case "continue_to_join": Text("Review the club’s current membership requirements before joining."); if invitation.postId != nil { Button("View club and join") { destination = true } }
        default: Text("This invitation is unavailable.")
        }
      } else if loading { ProgressView("Checking invitation") }
      if let error { Text(error).font(.subheadline); Button("Retry") { Task { await load() } }.disabled(loading) }
      Spacer()
    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(MIRATheme.Color.appBackground)
      .navigationTitle("Club invitation").navigationBarTitleDisplayMode(.inline)
      .task { if signedIn { await load() } }
      .navigationDestination(isPresented: $destination) {
        if let invitation {
          if invitation.state == "member" { CaptroTeaClubView(model: api.teaClubs.model(invitation.clubId), api: api).task { await api.teaClubs.model(invitation.clubId).load() } }
          else if let id = invitation.postId { CaptroClubPostDestination(id: id, api: api) }
        }
      }
  }
  private func load(accept: Bool = false) async {
    guard !loading else { return }; loading = true; error = nil; let owner = api.presentationScope; defer { loading = false }
    do {
      let result: CaptroClubInvitation
      if accept { result = try await api.post("/tea/club-invites/" + token, body: CaptroClubAction()) }
      else { result = try await api.getFresh("/tea/club-invites/" + token) }
      guard owner == api.presentationScope else { invitation = nil; return }; invitation = result
    } catch {
      invitation = nil
      if case MIRAAPIError.server(_, _, let detail) = error { self.error = detail ?? "This invitation is unavailable." }
      else { self.error = "Couldn’t check this invitation. Try again." }
    }
  }
}
