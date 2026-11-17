import SwiftUI
import UIKit

/// Only club rows probe membership. Events, meetups and the visitor purchase flow
/// retain their original destinations and authorization.
@MainActor struct CaptroTeaClubDestination: View {
  let entry: CaptroTeaEntry
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  @StateObject private var model: CaptroTeaClubModel
  init(entry: CaptroTeaEntry, api: MIRAAPIClient, viewerID: String?, signIn: @escaping () -> Void) {
    self.entry = entry; self.api = api; self.viewerID = viewerID; self.signIn = signIn
    _model = StateObject(wrappedValue: api.teaClubs.model(entry.destination.id))
  }
  var body: some View {
    Group {
      if viewerID == nil || model.denied {
        CaptroTeaDetailView(entry: entry, api: api, viewerID: viewerID, signIn: signIn)
      } else if model.club != nil {
        CaptroTeaClubView(model: model, api: api)
      } else {
        VStack(alignment: .leading, spacing: 16) {
          Text(entry.name).font(.title3.bold())
          if let error = model.error { Text(error); Button("Retry") { Task { await model.load(force: true) } } }
          else { ProgressView("Opening club") }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .background(MIRATheme.Color.appBackground)
      }
    }.task { if viewerID != nil { await model.load() } }
  }
}

@MainActor struct CaptroTeaClubView: View {
  @ObservedObject var model: CaptroTeaClubModel
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var sheet: ClubSheet?
  @State private var linkDestination: ClubLinkDestination?
  @State private var visible = false
  @State private var playingAttachmentID: String?
  @State private var scrollID: String?
  @State private var linkError: String?
  @State private var linkToSave: CaptroClubLinkDraft?
  @State private var externalLink: CaptroTeaLink?
  @FocusState private var composing: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      if let club = model.club, model.valid {
        Picker("Club section", selection: $model.tab) {
          Text("Chat").tag("Chat"); Text("Links").tag("Links"); Text("Info").tag("Info")
        }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8).accessibilityIdentifier("tea.club.tabs")
        ZStack {
          chat.opacity(model.tab == "Chat" ? 1 : 0).allowsHitTesting(model.tab == "Chat").accessibilityHidden(model.tab != "Chat")
          if model.tab == "Links" { links(club) }
          if model.tab == "Info" { info(club) }
        }
      } else { Text("You no longer have access to this club.").padding(); Spacer() }
    }
    .background(MIRATheme.Color.appBackground).foregroundStyle(MIRATheme.Color.textPrimary).tint(CaptroTeaStyle.accent)
    .toolbar(.hidden, for: .navigationBar).miraHideTabBarOnAppear()
    .safeAreaInset(edge: .bottom, spacing: 0) { if model.tab == "Chat", model.club != nil, model.valid { composer } }
    .sheet(item: $sheet) { destination in
      CaptroTeaClubManagement(model: model, api: api, section: destination.rawValue) { member in
        model.drafts[model.key, default: ""] += "@" + member.username + " "
        sheet = nil; composing = true
      }
    }
    .sheet(item: $linkToSave) { draft in CaptroClubLinkEditor(model: model, draft: draft) }
    .confirmationDialog("Open external link?", isPresented: Binding(get: { externalLink != nil }, set: { if !$0 { externalLink = nil } }), presenting: externalLink) { link in
      Button("Open " + link.hostname) {
        UIApplication.shared.open(link.url) { success in if !success { Task { @MainActor in linkError = "Couldn’t open this link. Try again." } } }
      }
      Button("Cancel", role: .cancel) {}
    }
    .navigationDestination(item: $linkDestination) { destination in
      switch destination {
      case .profile(let id): UserProfileNativeView(userId: id, api: api).tint(MIRATheme.Color.accent).toolbar(.visible, for: .navigationBar)
      case .post(let id): CaptroClubPostDestination(id: id, api: api).tint(MIRATheme.Color.accent).toolbar(.visible, for: .navigationBar)
      case .activity(let id): CaptroClubActivityLink(id: id, api: api, viewerID: model.club?.viewerId).tint(MIRATheme.Color.accent).toolbar(.visible, for: .navigationBar)
      case .invite(let token): CaptroTeaInviteView(token: token, api: api, signedIn: true).toolbar(.visible, for: .navigationBar)
      }
    }
    .task(id: "\(model.room ?? "general"):\(scenePhase == .active):\(model.tab):\(visible)") {
      guard scenePhase == .active, visible else { return }
      if model.tab == "Links" { await model.loadLinks() }
      await model.loadMessages()
      while !Task.isCancelled, model.valid {
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        guard !Task.isCancelled else { return }
        await model.load(force: true)
        if model.tab == "Chat" { await model.loadMessages(force: true) }
      }
    }
    .onChange(of: model.room) { old, new in
      if let scrollID { model.scrollIDs[old ?? "general"] = scrollID }
      scrollID = model.scrollIDs[new ?? "general"]
    }
    .onDisappear { visible = false; if let scrollID { model.scrollIDs[model.key] = scrollID } }
    .onAppear { visible = true; scrollID = model.scrollIDs[model.key] }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
        .accessibilityLabel("Back").accessibilityIdentifier("tea.club.back")
      CaptroTeaIdentity(name: model.club?.name ?? "", photo: model.club?.image, size: 36)
      VStack(alignment: .leading, spacing: 3) {
        Text(model.club?.name ?? "Club").font(.headline).fixedSize(horizontal: false, vertical: true)
        if let club = model.club {
          Text("\(club.memberCount) members" + (model.room.flatMap { selected in club.rooms.first { $0.id == selected }?.name }.map { " · " + $0 } ?? ""))
            .font(.caption).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      Menu {
        Button("Club information") { model.tab = "Info" }
        Button("Saved links") { model.tab = "Links" }
        if let club = model.club, club.roomsEnabled || club.canManage {
          Button("Rooms") { sheet = .rooms }.accessibilityIdentifier("tea.club.rooms")
        }
      } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
        .accessibilityLabel("Club menu").accessibilityIdentifier("tea.club.menu")
    }.padding(.horizontal, 8).padding(.vertical, 8)
  }
  private var chat: some View {
    VStack(spacing: 0) {
      if model.focusedHistory.contains(model.key) {
        Button("Latest messages") { Task { await model.loadMessages(latest: true); scrollID = model.messages.last?.id } }
          .frame(minHeight: 44).accessibilityIdentifier("tea.club.latest")
      }
      if let pin = model.club?.pin {
        Button { jump(pin) } label: {
          HStack(spacing: 8) { Image(systemName: "pin").font(.caption); Text(pin.body).font(.subheadline).lineLimit(1); Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption) }.frame(minHeight: 44).padding(.horizontal, 16)
        }.buttonStyle(.plain).accessibilityLabel("Pinned message: " + pin.body).accessibilityIdentifier("tea.club.pin")
        Divider()
      } else if let club = model.club, let legacy = club.legacyPin, !legacy.isEmpty {
        HStack(spacing: 8) { Image(systemName: "pin").font(.caption); Text(legacy).font(.subheadline).lineLimit(2); Spacer(minLength: 0) }
          .frame(minHeight: 44).padding(.horizontal, 16)
          .contextMenu {
            if club.canManage {
              Button("Unpin") { Task { do { try await model.perform("pin", .init(version: club.version)) } catch { model.actionError = "Couldn’t change the pin. Try again." } } }
            }
          }
        Divider()
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            if model.pages[model.key]?.cursor != nil { Button("Earlier messages") { Task { await model.loadMessages(older: true) } }.frame(minHeight: 44) }
            if model.messages.isEmpty {
              if model.pages[model.key] == nil, model.error == nil { ProgressView("Loading messages") }
              else if model.error == nil { Text("No messages yet. Start the conversation.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16) }
            }
            ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
              messageRow(message, showAuthor: index == 0 || model.messages[index - 1].author.id != message.author.id)
                .id(message.id)
                .onAppear { if scenePhase == .active, model.tab == "Chat" { Task { await model.markRead(message) } } }
            }
            if let error = model.error {
              Text(error).font(.footnote).foregroundStyle(.secondary)
              Button("Retry") { Task { await model.load(force: true); await model.loadMessages(force: true) } }.frame(minHeight: 44)
            }
            if let linkError { Text(linkError).font(.footnote).foregroundStyle(.secondary) }
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading).scrollTargetLayout()
        }.scrollPosition(id: $scrollID).defaultScrollAnchor(.top).scrollDismissesKeyboard(.interactively)
          .refreshable { await model.load(force: true); await model.loadMessages(force: true) }
          .onChange(of: model.messages.last?.id) { old, new in
            if old == nil, model.scrollIDs[model.key] == nil, let new { proxy.scrollTo(new, anchor: .bottom) }
          }
          .accessibilityIdentifier("tea.club.chat")
      }
    }
  }
  private func messageRow(_ message: CaptroClubMessage, showAuthor: Bool) -> some View {
    HStack(alignment: .top, spacing: 10) {
      if showAuthor {
        Button { linkDestination = .profile(message.author.id) } label: { CaptroTeaIdentity(name: message.author.name, photo: message.author.photoURL, size: 36) }
          .buttonStyle(.plain).accessibilityLabel("Open profile photo for " + message.author.name)
      } else { Color.clear.frame(width: 36, height: 1).accessibilityHidden(true) }
      VStack(alignment: .leading, spacing: 5) {
      if showAuthor {
        Button { linkDestination = .profile(message.author.id) } label: { Text(message.author.name).font(.subheadline.weight(.semibold)) }
          .buttonStyle(.plain).accessibilityLabel("Open profile for " + message.author.name)
      }
      if let quote = message.quote {
        Button { jump(quote) } label: { CaptroTeaQuote(text: quote.body).frame(minHeight: 44, alignment: .leading) }
          .buttonStyle(.plain).accessibilityLabel("Open quoted message: " + quote.body).accessibilityIdentifier("tea.club.quote." + message.id)
      }
      if !message.textWithoutLinks.isEmpty {
        Text(message.textWithoutLinks).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
          .accessibilityIdentifier("tea.club.message." + message.id)
      }
      if let media = message.mediaURL, !media.isEmpty {
        if message.mediaType == "file" || message.mediaType == "audio" || message.mediaType == "voice" {
        // The existing message view owns authorized attachment/video rendering.
        NavigationLink { ConversationNativeView(groupId: model.club?.groupId ?? "", title: model.club?.name ?? "Club", api: api).tint(MIRATheme.Color.accent) } label: { Label("Open attachment in Messages", systemImage: "photo").font(.subheadline).frame(minHeight: 44) }
        } else {
          CaptroClubAttachment(id: message.id, url: media, type: message.mediaType, playingID: $playingAttachmentID,
            active: visible && model.tab == "Chat" && model.valid && scenePhase == .active)
        }
      }
      if !message.links.isEmpty {
        TeaLinkFlow(spacing: 8) { ForEach(message.links) { link in quietLink(link).contextMenu { Button("Save to Links") { linkToSave = .init(url: link.url.absoluteString, message: message.id) } } } }
      }
      HStack(spacing: 12) {
        TeaConversationTime(value: message.createdAt)
        Spacer(minLength: 12)
        if !model.readOnly {
          Button("Reply") { model.quotes[model.key] = message.reference; composing = true }
            .font(.caption).frame(minHeight: 44).accessibilityLabel("Reply to " + message.author.name)
        }
      }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.top, showAuthor ? 12 : 4).padding(.bottom, 8)
      .overlay(alignment: .bottom) { Rectangle().fill(MIRATheme.Color.divider).frame(height: 0.5).accessibilityHidden(true) }
      .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      .contextMenu {
        if !model.readOnly { Button("Reply") { model.quotes[model.key] = message.reference } }
        ForEach(message.links) { link in Button("Save " + link.hostname + " to Links") { linkToSave = .init(url: link.url.absoluteString, message: message.id) } }
        if let club = model.club, club.canManage {
          Button(club.pin?.id == message.id ? "Unpin" : "Pin message") {
            Task { do { try await model.perform("pin", .init(message: club.pin?.id == message.id ? nil : message.id, version: club.version)) } catch { model.actionError = "Couldn’t change the pin. Refresh and try again." } }
          }
        }
      }
      .accessibilityAction(named: "Reply") { if !model.readOnly { model.quotes[model.key] = message.reference } }
  }
  private var composer: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let error = model.actionError { Text(error).font(.footnote).foregroundStyle(.secondary) }
      if model.readOnly { Text("Only organizers can post in this announcement room.").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 8) }
      else {
        if let quote = model.quotes[model.key] {
          HStack { Text(quote.body).font(.footnote).lineLimit(2); Spacer(); Button { model.quotes[model.key] = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.disabled(model.pending[model.key] != nil).accessibilityLabel("Clear quoted message") }
        }
        HStack(alignment: .bottom, spacing: 6) {
          Button { sheet = .mention } label: { Image(systemName: "at").frame(width: 44, height: 44) }.accessibilityLabel("Mention a member")
          TextField("Message the club…", text: Binding(get: { model.drafts[model.key, default: ""] }, set: { model.drafts[model.key] = $0 }), axis: .vertical)
            .lineLimit(1...5).padding(12).background(CaptroTeaStyle.tint, in: RoundedRectangle(cornerRadius: 22))
            .focused($composing).disabled(model.busy || model.pending[model.key] != nil).accessibilityIdentifier("tea.club.input")
          Button { Task { await model.send() } } label: {
            if model.busy { ProgressView().frame(width: 44, height: 44) } else { Image(systemName: "paperplane").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(CaptroTeaStyle.accent, in: Circle()) }
          }.disabled(model.busy || model.drafts[model.key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(model.drafts[model.key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel(model.pending[model.key] == nil ? "Send message" : "Retry message").accessibilityIdentifier("tea.club.send")
        }
      }
    }.padding(.horizontal, 12).padding(.vertical, 8).background(MIRATheme.Color.appBackground).overlay(alignment: .top) { Divider() }
  }
  private func links(_ club: CaptroTeaClub) -> some View {
    List {
      Button { linkToSave = .init() } label: { Label("Add link", systemImage: "plus").frame(minHeight: 44) }.accessibilityIdentifier("tea.club.add-link")
      if !model.linksLoaded && model.linksError == nil { ProgressView("Loading links") }
      if model.linksLoaded && model.links.isEmpty { Text("Save useful links here so members can find them again.").font(.subheadline).foregroundStyle(.secondary) }
      ForEach(model.links) { saved in
        VStack(alignment: .leading, spacing: 4) {
          Text(saved.title).font(.headline)
          if let link = CaptroTeaLink(saved.url) { quietLink(link) }
          if let user = saved.sharedBy {
            Button(saved.sharedName.map { "Shared by " + $0 } ?? "View sharer") { linkDestination = .profile(user) }.font(.caption).frame(minHeight: 44)
          }
          if let id = saved.messageId { Button("Original message") { jump(.init(id: id, body: saved.title, room: nil)) }.font(.caption).frame(minHeight: 44) }
        }.contextMenu {
          if club.canManage {
            Button("Edit link") { linkToSave = .init(saved: saved) }
            Button("Remove link", role: .destructive) { Task { do { try await model.perform("removeLink", .init(id: saved.id, version: saved.version)) } catch { model.linksError = "Couldn’t remove this link. Refresh and try again." } } }
          }
        }
      }
      if let error = model.linksError { Text(error).font(.footnote); Button("Retry") { Task { await model.loadLinks(force: true) } } }
      if model.linkCursor != nil { Button("More links") { Task { await model.loadLinks(more: true) } } }
    }.listStyle(.plain).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
      .refreshable { await model.loadLinks(force: true) }.accessibilityIdentifier("tea.club.links")
  }
  private func info(_ club: CaptroTeaClub) -> some View {
    List {
      if let description = club.description, !description.isEmpty { Section("About") { Text(description) } }
      if !club.rules.isEmpty { Section("Rules") { Text(club.rules) } }
      if !club.officialLinks.isEmpty { Section("Official links") { ForEach(club.officialLinks, id: \.self) { raw in if let link = CaptroTeaLink(raw) { quietLink(link) } } } }
      Button("Members · \(club.memberCount)") { sheet = .members }.frame(minHeight: 44)
      if club.canManage {
        Button("Invite members") { sheet = .invites }.frame(minHeight: 44).accessibilityIdentifier("tea.club.invites")
        Button("Edit rules and official links") { sheet = .settings }.frame(minHeight: 44)
      }
    }.listStyle(.plain).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground).accessibilityIdentifier("tea.club.info")
  }
  private func quietLink(_ link: CaptroTeaLink) -> some View {
    Button { open(link) } label: {
      HStack(spacing: 4) {
        if let platform = link.platform { Image("Tea" + platform, bundle: .module).renderingMode(.template).resizable().scaledToFit().frame(width: 11, height: 11) }
        else { Image(systemName: "link").font(.system(size: 11)) }
        Text(link.hostname).font(.subheadline).underline().fixedSize(horizontal: false, vertical: true)
      }.padding(.horizontal, 10).frame(minHeight: 44).background(CaptroTeaStyle.tint, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(CaptroTeaStyle.accent).accessibilityLabel("Open " + link.hostname)
  }
  private func open(_ link: CaptroTeaLink) {
    if let destination = ClubLinkDestination.parse(link) { linkDestination = destination; return }
    externalLink = link
  }
  private func jump(_ quote: CaptroClubQuote) {
    Task {
      do {
        let original = try await model.message(quote)
        if original.room == model.room, model.messages.contains(where: { $0.id == original.id }) { model.tab = "Chat"; scrollID = original.id }
        else {
          // Fetch one bounded page ending at the authorized original message.
          // Do not download an entire club history to jump to an older quote.
          model.tab = "Chat"; model.focusedHistory.insert(original.room ?? "general")
          model.room = original.room
          await model.loadMessages(through: original.id)
          if model.messages.contains(where: { $0.id == original.id }) { scrollID = original.id }
          else { linkError = "Couldn’t open the original message. Try again." }
        }
      } catch { linkError = "The original message is unavailable or access has changed." }
    }
  }
}

private enum ClubSheet: String, Identifiable { case rooms = "Rooms", invites = "Invites", members = "Members", mention = "Mention a member", settings = "Club settings"; var id: String { rawValue } }
enum ClubLinkDestination: Hashable, Identifiable {
  case profile(String), post(String), activity(String), invite(String)
  var id: Self { self }
  static func parse(_ link: CaptroTeaLink) -> Self? {
    if let route = CaptroTeaInviteRoute.parse(link.url) { return .invite(route.id) }
    if let profile = link.profile { return .profile(profile.id) }
    guard ["captro.app", "www.captro.app", "captro-site.pages.dev"].contains(link.url.host?.lowercased() ?? ""), link.url.query == nil, link.url.fragment == nil else { return nil }
    let parts = link.url.pathComponents.filter { $0 != "/" }
    if parts.count == 3, parts[0] == "tea", parts[1] == "activity", UUID(uuidString: parts[2]) != nil { return .activity(parts[2]) }
    if parts.count == 2, ["post", "posts"].contains(parts[0]), parts[1].range(of: "^[a-zA-Z0-9_-]{1,120}$", options: .regularExpression) != nil { return .post(parts[1]) }
    return nil
  }
}

struct CaptroClubPostDestination: View {
  let id: String
  let api: MIRAAPIClient
  @State private var post: MIRAPost?
  @State private var error = false
  @State private var retry = 0
  var body: some View {
    Group {
      if let post { PostDetailNativeView(post: post, api: api) }
      else if error { VStack { Text("This post is unavailable or couldn’t be loaded."); Button("Retry") { retry += 1 } }.padding() }
      else { ProgressView("Loading post") }
    }.task(id: retry) {
      do { let value: MIRAPost = try await api.getFresh("/posts/" + id); try Task.checkCancellation(); post = value }
      catch { if !Task.isCancelled { self.error = true } }
    }
  }
}
struct CaptroClubActivityLink: View {
  let id: String
  let api: MIRAAPIClient
  let viewerID: String?
  @State private var detail: CaptroTeaDetails?
  @State private var error = false
  @State private var retry = 0
  var body: some View {
    Group {
      if let detail { CaptroTeaDetailView(entry: detail.item, api: api, viewerID: viewerID, signIn: {}) }
      else if error { VStack { Text("This activity is unavailable or couldn’t be loaded."); Button("Retry") { retry += 1 } }.padding() }
      else { ProgressView("Loading activity") }
    }.task(id: retry) {
      do { let result: CaptroTeaDetails = try await api.getFresh("/tea/activity/" + id); try Task.checkCancellation(); detail = result }
      catch { if !Task.isCancelled { self.error = true } }
    }
  }
}

private struct CaptroClubAttachment: View {
  let id: String
  let url: String
  let type: String?
  @Binding var playingID: String?
  let active: Bool
  private var playing: Bool { playingID == id }
  private var video: Bool { type == "video" || url.isVideoURL }
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      RemoteMediaView(url: url, isVideo: video, shouldPlay: video && playing && active,
        maxPixelSize: 900, showsVideoPlaceholderIcon: true)
        .frame(maxWidth: 300).frame(height: 240).clipped()
      if video {
        Button(playing ? "Pause video" : "Play video") { playingID = playing ? nil : id }.frame(minHeight: 44)
      }
    }.onChange(of: active) { _, value in if !value && playing { playingID = nil } }
      .onChange(of: url) { _, _ in if playing { playingID = nil } }
      .onDisappear { if playing { playingID = nil } }
  }
}
