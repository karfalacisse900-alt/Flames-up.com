import SwiftUI
import UIKit

struct CaptroTeaConversationsList: View {
  let api: MIRAAPIClient
  let active: Bool
  let created: CaptroTeaConversation?
  let open: (CaptroTeaConversation) -> Void
  @State private var items: [CaptroTeaConversation] = []
  @State private var nextCursor: String?
  @State private var loading = false
  @State private var loaded = false
  @State private var error: String?
  @State private var scope = ""
  @State private var receivedAt: Date?
  @State private var revision = 0
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    List {
      if items.isEmpty {
        if loading { ProgressView("Loading Tea").listRowSeparator(.hidden) }
        else if error == nil, loaded { Text("No conversations yet. Start one with the pencil.").font(.subheadline).foregroundStyle(.secondary).listRowSeparator(.hidden) }
      }
      ForEach(items) { post in
        Button { open(post) } label: { CaptroTeaConversationRow(post: post) }
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
          .listRowSeparator(.hidden).listRowBackground(Color.clear)
          .accessibilityIdentifier("tea.conversation." + post.id)
      }
      if let error {
        VStack(alignment: .leading) {
          Text(error).font(.subheadline).foregroundStyle(.secondary)
          Button("Retry") { Task { await load(reset: nextCursor == nil, force: true) } }.frame(minHeight: 44)
        }.listRowSeparator(.hidden).listRowBackground(Color.clear)
      } else if nextCursor != nil {
        ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Color.clear)
          .task { await load(reset: false) }
      }
    }
    .listStyle(.plain).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
    .accessibilityIdentifier("tea.conversations.list")
    .refreshable { await load(reset: true, force: true) }
    .task(id: active) { if active { await load(reset: true) } }
    .onAppear { if active { Task { await load(reset: true) } } }
    .onChange(of: scenePhase) { _, phase in if phase == .active, active { Task { await load(reset: true) } } }
    .onChange(of: created) { _, post in
      guard let post, scope == api.presentationScope else { return }
      items.removeAll { $0.id == post.id }; items.insert(post, at: 0)
    }
    .onReceive(NotificationCenter.default.publisher(for: .captroTeaConversationChanged)) { notification in
      guard notification.userInfo?["scope"] as? String == scope, scope == api.presentationScope,
            let post = notification.object as? CaptroTeaConversation,
            let index = items.firstIndex(where: { $0.id == post.id }) else { return }
      items[index] = post
    }
    .onReceive(NotificationCenter.default.publisher(for: .captroTeaAccessChanged)) { _ in
      revision += 1
      items = []; nextCursor = nil; receivedAt = nil
      error = "Refresh to see available conversations."
    }
  }

  @MainActor private func load(reset: Bool, force: Bool = false) async {
    guard !loading, reset || nextCursor != nil else { return }
    if scope != api.presentationScope { items = []; nextCursor = nil; receivedAt = nil; loaded = false; scope = api.presentationScope }
    if reset, !force, let receivedAt, Date().timeIntervalSince(receivedAt) < 30 { return }
    let owner = scope
    let expectedRevision = revision
    loading = true; error = nil; defer { loading = false }
    do {
      let path = "/tea/conversations" + (!reset && nextCursor != nil ? "?cursor=" + nextCursor! : "")
      let page: CaptroTeaConversationPage<CaptroTeaConversation> = try await api.getFresh(path)
      guard owner == api.presentationScope, revision == expectedRevision, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : items.map(\.id))
      let unique = page.items.filter { seen.insert($0.id).inserted }
      items = reset ? unique : items + unique
      nextCursor = page.nextCursor; receivedAt = Date(); loaded = true
    } catch is CancellationError {} catch {
      guard owner == api.presentationScope, revision == expectedRevision else { return }
      if case MIRAAPIError.server(400, "TEA_DISCUSSION_INVALID", _) = error { nextCursor = nil; receivedAt = nil }
      self.error = "Couldn’t load conversations. Try again."
    }
  }
}

private struct CaptroTeaConversationRow: View {
  let post: CaptroTeaConversation
  private var navy: Bool { (post.id.utf8.last ?? 0) % 2 == 0 }
  var body: some View {
    HStack(spacing: 10) {
      TeaIcon(symbol: "person.3.fill", palette: navy ? .navy : .sage)
      ViewThatFits(in: .horizontal) {
        HStack {
          Text(post.title).font(.subheadline.weight(.semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 8); TeaConversationTime(value: post.createdAt)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(post.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
          TeaConversationTime(value: post.createdAt)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
    }.foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: 48)
      .background(MIRATheme.Color.surface, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MIRATheme.Color.divider))
  }
}

private struct TeaConversationTime: View {
  let value: String
  var body: some View {
    if let date = captroTeaDate(value) {
      Text(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

@MainActor struct CaptroTeaConversationDetail: View {
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  @StateObject private var model: CaptroTeaConversationModel
  @State private var editing = false
  @State private var profile: CaptroProfileLink?
  @State private var linkError: String?
  @Environment(\.scenePhase) private var scenePhase

  init(post: CaptroTeaConversation, api: MIRAAPIClient, viewerID: String?, signIn: @escaping () -> Void) {
    self.api = api; self.viewerID = viewerID; self.signIn = signIn
    _model = StateObject(wrappedValue: api.teaConversations.model(for: post))
  }

  var body: some View {
    List {
      if let post = model.post, model.valid {
        VStack(alignment: .leading, spacing: 12) {
          Text(post.title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
              Text(post.author.name).font(.subheadline.weight(.semibold))
              HStack(spacing: 6) {
                if !post.author.username.isEmpty {
                  Text("@" + post.author.username).font(.caption).foregroundStyle(.secondary)
                }
                TeaConversationTime(value: post.createdAt)
              }
            }
            Spacer(minLength: 8)
            Button(post.following ? "Following" : "Follow") {
              if viewerID == nil { signIn() } else { Task { await model.follow() } }
            }.font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
              .disabled(model.busy).accessibilityLabel(post.following ? "Unfollow discussion" : "Follow discussion")
              .accessibilityIdentifier("tea.conversation.follow")
          }
          Text(post.body).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          let links = post.links.compactMap(CaptroTeaLink.init)
          if !links.isEmpty {
            TeaLinkFlow(spacing: 8) {
              ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                HStack(spacing: 7) {
                  if index > 0 { Text("·").foregroundStyle(.secondary).accessibilityHidden(true) }
                  Button { open(link) } label: {
                    HStack(spacing: 4) {
                      if let platform = link.platform {
                        Image("Tea" + platform, bundle: .module).renderingMode(.template).resizable().scaledToFit()
                          .frame(width: 11, height: 11).accessibilityHidden(true)
                      } else { Image(systemName: "link").font(.system(size: 11)).accessibilityHidden(true) }
                      Text(link.hostname).font(.subheadline).underline().fixedSize(horizontal: false, vertical: true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                  }.buttonStyle(.plain).foregroundStyle(MIRATheme.Color.textPrimary)
                    .accessibilityLabel("Open \(link.hostname)\(link.profile == nil ? " in browser" : " in Captro")")
                    .accessibilityIdentifier("tea.link." + link.hostname)
                }
              }
            }
          }
          if let linkError { Text(linkError).font(.footnote).foregroundStyle(.secondary) }
        }.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
          .listRowSeparator(.hidden).listRowBackground(Color.clear)
        ForEach(model.replies) { reply in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(reply.author.name).font(.subheadline.weight(.semibold))
              Spacer(); TeaConversationTime(value: reply.createdAt)
            }
            Text(reply.body).font(.body).fixedSize(horizontal: false, vertical: true)
          }.padding(.vertical, 6).listRowBackground(Color.clear)
            .accessibilityIdentifier("tea.reply." + reply.id)
        }
        if model.loadingReplies { ProgressView("Loading replies").listRowSeparator(.hidden) }
        if model.nextCursor != nil {
          Button("More replies") { Task { await model.loadReplies(reset: false) } }.frame(minHeight: 44).disabled(model.loadingReplies)
        }
        if let error = model.replyError {
          VStack(alignment: .leading) {
            Text(error).font(.footnote).foregroundStyle(.secondary)
            Button("Retry") { Task {
              if model.replySubmissionFailed { await model.sendReply() } else { await model.loadReplies(reset: model.nextCursor == nil, force: true) }
            } }.frame(minHeight: 44).disabled(model.busy)
          }.listRowSeparator(.hidden)
        }
      }
      if let error = model.error {
        VStack(alignment: .leading) {
          Text(error).font(.subheadline).foregroundStyle(.secondary)
          Button("Retry") { Task { await model.load(force: true) } }.frame(minHeight: 44)
        }.listRowSeparator(.hidden).listRowBackground(Color.clear)
      }
      if model.loading, model.post == nil {
        ProgressView("Loading post").listRowSeparator(.hidden).listRowBackground(Color.clear)
      }
    }.listStyle(.plain).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
      .navigationTitle("").navigationBarTitleDisplayMode(.inline).miraNavigationSurface()
      .accessibilityIdentifier("tea.conversation.detail")
      #if DEBUG
      .overlay(alignment: .bottomTrailing) { TeaReviewRequestCounter().allowsHitTesting(false) }
      #endif
      .toolbar {
        if model.post?.isAuthor == true {
          ToolbarItem(placement: .topBarTrailing) {
            Button { editing = true } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
              .accessibilityLabel("Edit Tea post").accessibilityIdentifier("tea.conversation.edit")
          }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if model.post != nil, model.valid {
          HStack(alignment: .bottom, spacing: 10) {
            if viewerID == nil { Button("Sign in to reply", action: signIn).frame(maxWidth: .infinity, minHeight: 44) }
            else {
              TextField("Write a reply…", text: $model.draft, axis: .vertical).lineLimit(1...5)
                .disabled(model.busy || model.replyPending)
                .font(.body).padding(10).background(MIRATheme.Color.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MIRATheme.Color.divider))
                .accessibilityIdentifier("tea.reply.input")
              Button { Task { await model.sendReply() } } label: {
                if model.busy { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44) }
              }.disabled(model.busy || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 4000)
                .accessibilityLabel("Send reply").accessibilityIdentifier("tea.reply.send")
            }
          }.padding(.horizontal, 14).padding(.vertical, 8).background(MIRATheme.Color.appBackground)
            .overlay(alignment: .top) { Divider() }
        }
      }
      .sheet(isPresented: $editing) {
        if let post = model.post { CaptroTeaComposer(api: api, editing: post) { model.updated($0) } }
      }
      .navigationDestination(isPresented: Binding(get: { profile != nil }, set: { if !$0 { profile = nil } })) {
        if let profile { UserProfileNativeView(userId: profile.id, api: api) }
      }
      .task { await model.load() }
      .refreshable { await model.load(force: true) }
      .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
  }

  private func open(_ link: CaptroTeaLink) {
    linkError = nil
    if let destination = link.profile { profile = destination; return }
    UIApplication.shared.open(link.url, options: [:]) { success in
      if !success { Task { @MainActor in linkError = "Couldn’t open this website. Try again." } }
    }
  }
}

/// Wrap whole link controls instead of squeezing them into one horizontal line.
private struct TeaLinkFlow: Layout {
  let spacing: CGFloat
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(width: proposal.width ?? 320, subviews: subviews).size
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = arrange(width: bounds.width, subviews: subviews)
    for (index, point) in result.points.enumerated() {
      subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
  }
  private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
    var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
    var points: [CGPoint] = []
    for view in subviews {
      let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
      if x > 0, x + size.width > width { x = 0; y += line; line = 0 }
      points.append(CGPoint(x: x, y: y)); x += size.width + spacing; line = max(line, size.height)
    }
    return (CGSize(width: width, height: y + line), points)
  }
}

struct CaptroTeaComposer: View {
  let api: MIRAAPIClient
  let editing: CaptroTeaConversation?
  let saved: (CaptroTeaConversation) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var bodyText: String
  @State private var links: [String]
  @State private var saving = false
  @State private var error: String?
  @State private var requestID = UUID().uuidString
  @State private var submitted: Payload?

  init(api: MIRAAPIClient, editing: CaptroTeaConversation? = nil, saved: @escaping (CaptroTeaConversation) -> Void) {
    self.api = api; self.editing = editing; self.saved = saved
    _title = State(initialValue: editing?.title ?? "")
    _bodyText = State(initialValue: editing?.body ?? "")
    _links = State(initialValue: editing?.links ?? [])
  }
  private struct Payload: Encodable { let title, body: String; let links: [String]; let requestID: String?; let version: Int? }
  private var valid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 160 &&
    !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.count <= 8000 &&
    links.allSatisfy { CaptroTeaLink($0) != nil }
  }
  var body: some View {
    NavigationStack {
      Form {
        Group {
        TextField("Title", text: $title, axis: .vertical).accessibilityIdentifier("tea.compose.title")
        TextField("Start a discussion…", text: $bodyText, axis: .vertical).lineLimit(5...14).accessibilityIdentifier("tea.compose.body")
        Section {
          ForEach(links.indices, id: \.self) { index in
            HStack {
              TextField("https://", text: $links[index]).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Link \(index + 1)").accessibilityIdentifier("tea.compose.link.\(index)")
              Button { links.remove(at: index) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Remove link \(index + 1)")
            }
          }
          if links.count < 3 { Button("Add link") { links.append("") }.frame(minHeight: 44) }
        } footer: { Text("Optional. Up to three HTTPS links. Only you can edit the links on your post.") }
        }.disabled(saving || submitted != nil)
        if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
      }.disabled(saving).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
        .navigationTitle(editing == nil ? "New Tea post" : "Edit post").navigationBarTitleDisplayMode(.inline).miraNavigationSurface()
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
          ToolbarItem(placement: .confirmationAction) {
            Button(saving ? "Saving…" : submitted != nil ? "Retry" : editing == nil ? "Post" : "Save") { Task { await save() } }
              .disabled(!valid || saving).accessibilityIdentifier("tea.compose.save")
          }
        }.interactiveDismissDisabled(saving)
    }
  }
  @MainActor private func save() async {
    guard valid, !saving else { return }
    saving = true; error = nil; defer { saving = false }
    let owner = api.presentationScope
    // Retain a request's exact payload after an ambiguous response; subsequent
    // retry resolves that operation instead of silently creating another post.
    let payload = submitted ?? Payload(title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
      links: links.compactMap { CaptroTeaLink($0)?.url.absoluteString }, requestID: editing == nil ? requestID : nil, version: editing?.version)
    submitted = payload
    do {
      let result: CaptroTeaConversation
      if let editing { result = try await api.put("/tea/conversations/" + editing.id, body: payload) }
      else { result = try await api.post("/tea/conversations", body: payload) }
      guard owner == api.presentationScope else { return }
      saved(result); dismiss()
    } catch {
      guard owner == api.presentationScope else { return }
      switch error {
      case MIRAAPIError.server(let status, _, let message) where [400,403,404,409].contains(status):
        submitted = nil
        self.error = message ?? "Couldn’t save this post. Check the details and try again."
      default:
        self.error = "Post wasn’t confirmed. Retry checks the same post before making changes. Your draft is still here."
      }
    }
  }
}
