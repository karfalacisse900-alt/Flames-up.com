import SwiftUI
import UIKit

// Tea-only treatments; global navigation and other Captro surfaces keep their theme.
enum CaptroTeaStyle {
  static let accent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(red: 0.73, green: 0.58, blue: 1, alpha: 1) : UIColor(red: 0.43, green: 0.16, blue: 0.78, alpha: 1)
  })
  static let tint = accent.opacity(0.08)
  static let separator = Color(uiColor: UIColor { traits in
    UIColor(white: traits.userInterfaceStyle == .dark ? 0.28 : 0.83, alpha: 1)
  })
}

struct CaptroTeaHeading: View {
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    CaptroBrandLogo(onDark: colorScheme == .dark)
      .frame(width: 86, height: 23)
      .accessibilityIdentifier("tea.heading")
  }
}

struct CaptroTeaIdentity: View {
  let name: String
  var photo: String? = nil
  var size: CGFloat = 40
  var body: some View {
    Group {
      if let photo, !photo.isEmpty { RemoteAvatar(url: photo, size: size) }
      else {
        Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined())
          .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
          .frame(width: size, height: size).background(CaptroTeaStyle.tint, in: Circle())
      }
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}

struct CaptroTeaQuote: View {
  let text: String
  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: "quote.opening").font(.caption).foregroundStyle(CaptroTeaStyle.accent).accessibilityHidden(true)
      Text(text).font(.subheadline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
      .background(CaptroTeaStyle.tint, in: RoundedRectangle(cornerRadius: 8))
  }
}

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
  @State private var requestID: UUID?
  @Environment(\.scenePhase) private var scenePhase

  init(api: MIRAAPIClient, active: Bool, created: CaptroTeaConversation?, open: @escaping (CaptroTeaConversation) -> Void) {
    self.api = api; self.active = active; self.created = created; self.open = open
    let cached = api.teaConversations.cachedListing()
    _items = State(initialValue: cached?.items ?? [])
    _nextCursor = State(initialValue: cached?.cursor)
    _receivedAt = State(initialValue: cached?.receivedAt)
    _loaded = State(initialValue: cached != nil)
    _scope = State(initialValue: api.presentationScope)
  }

  var body: some View {
    List {
      if items.isEmpty {
        if loading && error == nil { ProgressView("Loading conversations…").listRowSeparator(.hidden).accessibilityIdentifier("tea.conversations.loading") }
        else if error == nil, loaded { Text("No conversations yet. Tap Post to start one.").font(.subheadline).foregroundStyle(.secondary).listRowSeparator(.hidden) }
      }
      ForEach(items) { post in
        Button { open(post) } label: { CaptroTeaConversationRow(post: post) }
          .background(CaptroFeedViewportMarker(owner: api.teaConversations.listViewport,
            postID: post.id, feed: "tea-list").allowsHitTesting(false))
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
    .task(id: "\(active)-\(revision)") { if active { await load(reset: true) } }
    .onAppear {
      api.teaConversations.listViewport.select("tea-list")
      api.teaConversations.listViewport.updateOrder(items.map(\.id))
      api.teaConversations.listViewport.setActive(active)
    }
    .onDisappear { api.teaConversations.listViewport.setActive(false) }
    .onChange(of: active) { _, active in api.teaConversations.listViewport.setActive(active) }
    .onChange(of: items) { _, items in
      api.teaConversations.listViewport.updateOrder(items.map(\.id))
      if scope == api.presentationScope, let receivedAt {
        api.teaConversations.saveListing(items, cursor: nextCursor, receivedAt: receivedAt)
      }
    }
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
      requestID = nil; loading = false; loaded = false
      items = []; nextCursor = nil; receivedAt = nil; error = nil
      revision += 1 // The task restarts an authorized read; never leave an idle loading label.
    }
  }

  @MainActor private func load(reset: Bool, force: Bool = false) async {
    guard !loading, reset || nextCursor != nil else { return }
    if scope != api.presentationScope { items = []; nextCursor = nil; receivedAt = nil; loaded = false; scope = api.presentationScope }
    if reset, !force, let receivedAt, Date().timeIntervalSince(receivedAt) < 30 { return }
    let owner = scope
    let expectedRevision = revision
    let token = UUID(); requestID = token
    loading = true; error = nil; defer { if requestID == token { loading = false; requestID = nil } }
    do {
      let path = "/tea/conversations" + (!reset && nextCursor != nil ? "?cursor=" + nextCursor! : "")
      let page: CaptroTeaConversationPage<CaptroTeaConversation> = try await api.getFresh(path)
      guard requestID == token, owner == api.presentationScope, revision == expectedRevision, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : items.map(\.id))
      let unique = page.items.filter { seen.insert($0.id).inserted }
      items = reset ? unique : items + unique
      nextCursor = page.nextCursor; receivedAt = Date(); loaded = true
      api.teaConversations.saveListing(items, cursor: nextCursor, receivedAt: receivedAt!)
    } catch is CancellationError {} catch {
      guard requestID == token, owner == api.presentationScope, revision == expectedRevision, !Task.isCancelled, !CaptroRefreshFailure.isCancellation(error) else { return }
      if case MIRAAPIError.server(400, "TEA_DISCUSSION_INVALID", _) = error { nextCursor = nil; receivedAt = nil }
      self.error = CaptroRefreshFailure.message(error, content: "conversations", cached: !items.isEmpty)
    }
  }
}

private struct CaptroTeaConversationRow: View {
  let post: CaptroTeaConversation
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      CaptroTeaIdentity(name: post.author.name, photo: post.author.photoURL, size: 48)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(post.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          replyCount.fixedSize(horizontal: true, vertical: false)
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        Text(post.body).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("tea.preview." + post.id)
        TeaLinkFlow(spacing: 5) {
          Text(post.author.name).font(.footnote).foregroundStyle(.secondary)
          Text("·").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
          TeaConversationTime(value: post.createdAt)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.foregroundStyle(MIRATheme.Color.textPrimary).padding(.vertical, 16)
      .overlay(alignment: .bottom) { Rectangle().fill(CaptroTeaStyle.separator).frame(height: 1).accessibilityHidden(true) }.contentShape(Rectangle())
  }
  @ViewBuilder private var replyCount: some View {
    if let count = post.replyCount {
      Text("\(count) \(count == 1 ? "reply" : "replies")").font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct TeaConversationTime: View {
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
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  init(post: CaptroTeaConversation, api: MIRAAPIClient, viewerID: String?, signIn: @escaping () -> Void) {
    self.api = api; self.viewerID = viewerID; self.signIn = signIn
    _model = StateObject(wrappedValue: api.teaConversations.model(for: post))
  }

  var body: some View {
    List {
      if let post = model.post, model.valid {
        VStack(alignment: .leading, spacing: 12) {
          authorHeader(post)
          Text(post.title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
          if let sentences = post.sentences, !sentences.isEmpty {
            ForEach(sentences) { sentence in
              VStack(alignment: .leading, spacing: 6) {
                Text(sentence.quote).font(.body).fixedSize(horizontal: false, vertical: true)
                  .textSelection(.enabled)
                  .contextMenu { Button("Reply to this part") { target(sentence) } }
                  .accessibilityAction(named: "Reply to this part") { target(sentence) }
                  .accessibilityIdentifier("tea.sentence." + sentence.id)
                sentenceThread(sentence, post: post)
              }
            }
            ForEach((post.replyTargets ?? []).filter { count in !sentences.contains { $0.id == count.target.id } }, id: \.target.id) { count in
              VStack(alignment: .leading, spacing: 4) {
                Text("Earlier text").font(.caption).foregroundStyle(.secondary)
                Text(count.target.quote).font(.subheadline).foregroundStyle(.secondary)
                sentenceThread(count.target, post: post)
              }
            }
          } else {
            Text(post.body).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          }
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
                  }.buttonStyle(.plain).foregroundStyle(CaptroTeaStyle.accent)
                    .accessibilityLabel("Open \(link.hostname)\(link.profile == nil ? " in browser" : " in Captro")")
                    .accessibilityIdentifier("tea.link." + link.hostname)
                }
              }
            }
          }
          if let linkError { Text(linkError).font(.footnote).foregroundStyle(.secondary) }
        }.background(CaptroFeedViewportMarker(owner: model.viewport, postID: "caption", feed: "tea:" + model.id).allowsHitTesting(false))
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
          .listRowSeparator(.hidden).listRowBackground(Color.clear)
        if let error = model.authorError {
          HStack { Text(error).font(.footnote).foregroundStyle(.secondary); Button("Retry profile") { Task { await model.loadAuthor() } }.frame(minHeight: 44) }
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
        }
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(post.replyCount.map { "Replies (\($0))" } ?? "Replies").font(.headline)
            if !(post.replyTargets ?? []).isEmpty { Text("General replies").font(.caption).foregroundStyle(.secondary) }
            if model.nextCursor != nil {
              Text("\(model.replies.filter { $0.target == nil }.count) general replies loaded").font(.caption).foregroundStyle(.secondary)
            }
          }
          Spacer()
          Button {
            if viewerID == nil { signIn() } else { Task { await model.follow() } }
          } label: { Image(systemName: post.following ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44) }
            .buttonStyle(.plain).disabled(model.busy)
            .accessibilityLabel(post.following ? "Unfollow discussion" : "Follow discussion")
            .accessibilityIdentifier("tea.conversation.follow")
        }.listRowSeparator(.hidden).listRowBackground(Color.clear)
        TeaReplyGroups(replies: model.replies.filter { $0.target == nil })
          .background(CaptroFeedViewportMarker(owner: model.viewport, postID: "general", feed: "tea:" + model.id).allowsHitTesting(false))
          .listRowSeparator(.hidden).listRowBackground(Color.clear)
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
      .tint(CaptroTeaStyle.accent)
      .miraHideTabBarOnAppear()
      .navigationBarBackButtonHidden(true)
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .top, spacing: 0) {
        HStack(spacing: 12) {
          Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
            .accessibilityLabel("Back").accessibilityIdentifier("tea.detail.back")
          Spacer(minLength: 0)
          CaptroTeaHeading()
          Spacer(minLength: 0)
          if model.post?.isAuthor == true, model.valid {
            Button { editing = true } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
              .buttonStyle(.plain).accessibilityLabel("Edit Tea post").accessibilityIdentifier("tea.conversation.edit")
          } else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
        }.padding(.horizontal, 8).padding(.vertical, 4).background(MIRATheme.Color.appBackground)
          .overlay(alignment: .bottom) { Rectangle().fill(MIRATheme.Color.divider).frame(height: 0.5).accessibilityHidden(true) }
      }

      .safeAreaInset(edge: .bottom, spacing: 0) {
        if model.post != nil, model.valid {
          VStack(alignment: .leading, spacing: 8) {
          if let target = model.replyTarget {
            HStack(alignment: .top) {
              Rectangle().fill(CaptroTeaStyle.accent.opacity(0.25)).frame(width: 2)
              VStack(alignment: .leading, spacing: 3) {
                Text("Replying to this line").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("tea.reply.target")
                Text(target.quote).font(.subheadline).lineLimit(2)
              }
              Spacer(minLength: 0)
              Button { model.selectTarget(nil) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .disabled(model.busy || model.replyPending).accessibilityLabel("Clear reply target")
                .accessibilityIdentifier("tea.reply.clear-target")
            }.fixedSize(horizontal: false, vertical: true)
          }
          HStack(alignment: .bottom, spacing: 10) {
            if viewerID == nil { Button("Sign in to reply", action: signIn).frame(maxWidth: .infinity, minHeight: 44) }
            else {
              TextField("Write a reply…", text: $model.draft, axis: .vertical).lineLimit(1...5)
                .disabled(model.busy || model.replyPending)
                .font(.body).padding(12).background(CaptroTeaStyle.tint, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("tea.reply.input")
              Button { Task { await model.sendReply() } } label: {
                if model.busy { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "paperplane").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(CaptroTeaStyle.accent, in: Circle()) }
              }.disabled(model.busy || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 4000)
                .opacity(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .accessibilityLabel(model.replySubmissionFailed ? "Retry reply" : "Send reply").accessibilityIdentifier("tea.reply.send")
            }
          }
          }.padding(.horizontal, 14).padding(.vertical, 8).background(MIRATheme.Color.appBackground)
            .overlay(alignment: .top) { Divider() }
        }
      }
      .sheet(isPresented: $editing) {
        if let post = model.post { CaptroTeaComposer(api: api, editing: post) { model.updated($0) } }
      }
      .navigationDestination(isPresented: Binding(get: { profile != nil }, set: { if !$0 { profile = nil } })) {
        if let profile { UserProfileNativeView(userId: profile.id, api: api).tint(MIRATheme.Color.accent).toolbar(.visible, for: .navigationBar) }
      }
      .task { await model.load() }
      .onAppear { model.viewport.setActive(true) }
      .onDisappear { model.viewport.setActive(false) }
      .refreshable { await model.load(force: true) }
      .onChange(of: scenePhase) { _, phase in
        model.viewport.setActive(phase == .active)
        if phase == .active { Task { await model.load() } }
      }
  }

  private func authorHeader(_ post: CaptroTeaConversation) -> some View {
    HStack(spacing: 10) {
      Button { profile = CaptroProfileLink(id: post.author.id) } label: {
        CaptroTeaIdentity(name: post.author.name, photo: post.author.photoURL ?? model.authorProfile?.profileImage, size: 44)
      }.buttonStyle(.plain).accessibilityLabel("Open profile photo for " + post.author.name)
        .accessibilityIdentifier("tea.author.avatar")
      Button { profile = CaptroProfileLink(id: post.author.id) } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(post.author.name).font(.headline)
          Text("@" + post.author.username).font(.subheadline).foregroundStyle(.secondary)
          TeaConversationTime(value: post.createdAt)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityLabel("Open profile for " + post.author.name)
        .accessibilityIdentifier("tea.author.profile")
      if !post.isAuthor {
        Button {
          if viewerID == nil { signIn() } else { Task { await model.followAuthor() } }
        } label: {
          Image(systemName: model.authorProfile?.viewerFollowing == true ? "checkmark" : model.authorProfile?.followPending == true ? "clock" : "plus")
            .font(.headline).frame(width: 40, height: 28)
            .overlay(Capsule().strokeBorder(CaptroTeaStyle.accent)).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(CaptroTeaStyle.accent).disabled(model.followingAuthor)
          .accessibilityLabel(model.authorProfile?.viewerFollowing == true ? "Unfollow author" : model.authorProfile?.followPending == true ? "Cancel follow request" : "Follow author")
          .accessibilityIdentifier("tea.author.follow")
      }
    }.foregroundStyle(MIRATheme.Color.textPrimary).padding(.bottom, 4)
  }
  private func target(_ sentence: CaptroTeaReplyTarget) {
    if viewerID == nil { signIn() } else { model.selectTarget(sentence) }
  }
  @ViewBuilder private func sentenceThread(_ target: CaptroTeaReplyTarget, post: CaptroTeaConversation) -> some View {
    let count = post.replyTargets?.first { $0.target.id == target.id }?.count ?? 0
    if count > 0 {
      let expanded = model.expandedTargets.contains(target.id)
      Button {
        if expanded { model.expandedTargets.remove(target.id) } else {
          model.expandedTargets.insert(target.id)
          Task { await model.loadThread(target) }
        }
      } label: { Text(expanded ? "Hide replies" : "\(count) \(count == 1 ? "reply" : "replies") to this line").font(.subheadline).underline().frame(minHeight: 44) }
        .buttonStyle(.plain).accessibilityIdentifier("tea.thread." + target.id)
      if expanded {
        VStack(alignment: .leading, spacing: 8) {
          CaptroTeaQuote(text: target.quote)
          TeaReplyGroups(replies: model.threads[target.id] ?? [])
          if model.loadingThreads.contains(target.id) { ProgressView("Loading replies") }
          if let error = model.threadErrors[target.id] {
            Text(error).font(.footnote)
            Button("Retry replies") { Task { await model.loadThread(target, reset: true) } }.frame(minHeight: 44)
          }
          if model.threadCursors[target.id] != nil {
            Button("Load more replies") { Task { await model.loadThread(target) } }.frame(minHeight: 44).disabled(model.loadingThreads.contains(target.id))
          }
        }.padding(.leading, 14).overlay(alignment: .leading) { Rectangle().fill(CaptroTeaStyle.accent.opacity(0.25)).frame(width: 2) }
      }
    }
  }

  private func open(_ link: CaptroTeaLink) {
    linkError = nil
    if let destination = link.profile { profile = destination; return }
    UIApplication.shared.open(link.url, options: [:]) { success in
      if !success { Task { @MainActor in linkError = "Couldn’t open this website. Try again." } }
    }
  }
}


private struct TeaReplyGroups: View {
  let replies: [CaptroTeaReply]
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(CaptroTeaReplyGroup.consecutive(replies)) { group in
        HStack(alignment: .top, spacing: 10) {
          CaptroTeaIdentity(name: group.replies[0].author.name, photo: group.replies[0].author.photoURL, size: 36)
          VStack(alignment: .leading, spacing: 8) {
            Text(group.replies[0].author.name).font(.subheadline.weight(.semibold))
            ForEach(group.replies) { reply in
              VStack(alignment: .leading, spacing: 4) {
                Text(reply.body).font(.body).fixedSize(horizontal: false, vertical: true)
                TeaConversationTime(value: reply.createdAt)
              }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("tea.reply." + reply.id)
            }
          }
        }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .bottom) { Rectangle().fill(MIRATheme.Color.divider).frame(height: 0.5).accessibilityHidden(true) }
      }
    }
  }
}

/// Wrap whole link controls instead of squeezing them into one horizontal line.
struct TeaLinkFlow: Layout {
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
