import SwiftUI
import UIKit

// Tea-only treatments; global navigation and other Captro surfaces keep their theme.
enum CaptroTeaStyle {
  static let accent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(red: 0.73, green: 0.58, blue: 1, alpha: 1) : UIColor(red: 0.43, green: 0.16, blue: 0.78, alpha: 1)
  })
  static let tint = accent.opacity(0.08)
  static let composerFill = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.95, green: 0.945, blue: 0.96, alpha: 1)
  })
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
      Text(text).font(.subheadline).italic().lineLimit(3).fixedSize(horizontal: false, vertical: true)
    }.padding(.horizontal, 10).padding(.vertical, 5)
      .background(CaptroTeaStyle.tint, in: RoundedRectangle(cornerRadius: 12))
  }
}

struct CaptroTeaConversationsList: View {
  let api: MIRAAPIClient
  let active: Bool
  let viewerID: String?
  let signIn: () -> Void
  let created: CaptroTeaConversation?
  let open: (CaptroTeaConversation) -> Void
  @StateObject private var model: CaptroTeaNotesListModel
  @State private var actionDestination: CaptroTeaNoteDestination?
  @Environment(\.scenePhase) private var scenePhase

  init(api: MIRAAPIClient, active: Bool, viewerID: String?, signIn: @escaping () -> Void, created: CaptroTeaConversation?, open: @escaping (CaptroTeaConversation) -> Void) {
    self.viewerID = viewerID; self.signIn = signIn
    self.api = api; self.active = active; self.created = created; self.open = open
    _model = StateObject(wrappedValue: api.teaConversations.notesList())
  }

  var body: some View {
    List {
      if model.items.isEmpty {
        if model.loading && model.error == nil { ProgressView("Loading Notes…").listRowSeparator(.hidden).accessibilityIdentifier("tea.conversations.loading") }
        else if model.error == nil, model.loaded { Text("No Notes yet. Tap Post to start one.").font(.subheadline).foregroundStyle(MIRATheme.Color.textSecondary).listRowSeparator(.hidden) }
      }
      ForEach(model.items) { post in
        VStack(alignment: .leading, spacing: 0) {
          CaptroTeaConversationRow(post: post, signal: api.teaConversations.signal(for: post),
            signedIn: viewerID != nil, signIn: signIn, open: { open(post) })
          if post.primaryAction != nil {
            CaptroTeaNoteActionView(note: post, api: api, viewerID: viewerID, signIn: signIn) { actionDestination = $0 }
              .padding(.leading, MIRATheme.Layout.rowAvatar + MIRATheme.Layout.avatarGap).padding(.bottom, 8)
          }
        }.overlay(alignment: .bottom) { MIRAHairline(color: CaptroTeaStyle.separator) }
          .background(CaptroFeedViewportMarker(owner: api.teaConversations.listViewport,
            postID: post.id, feed: "tea-list").allowsHitTesting(false))
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets(top: 0, leading: MIRATheme.Layout.listInset, bottom: 0, trailing: MIRATheme.Layout.listInset))
          .listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
      }
      if let error = model.error {
        VStack(alignment: .leading) {
          Text(error).font(.subheadline).foregroundStyle(MIRATheme.Color.textSecondary)
          Button("Retry") { Task { await model.retry() } }.frame(minHeight: 44)
        }.listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
      } else if model.nextCursor != nil {
        ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
          .task(id: "\(model.nextCursor ?? "")-\(active)") { if active { await model.load(reset: false) } }
      }
    }
    .listStyle(.plain).listRowSpacing(0).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
    .accessibilityIdentifier("tea.conversations.list")
    .navigationDestination(item: $actionDestination) { destination in
      CaptroTeaNoteDestinationView(destination: destination, api: api, viewerID: viewerID, signIn: signIn)
    }
    .refreshable { await model.load(reset: true, force: true) }
    .task(id: "\(active)-\(model.revision)") {
      api.teaConversations.listViewport.setActive(active)
      if active { await model.load(reset: true) }
    }
    .onAppear {
      api.teaConversations.listViewport.select("tea-list")
      api.teaConversations.listViewport.updateOrder(model.items.map(\.id))
      api.teaConversations.listViewport.setActive(active)
    }
    .onDisappear { api.teaConversations.listViewport.setActive(false) }
    .onChange(of: active) { _, active in api.teaConversations.listViewport.setActive(active) }
    .onChange(of: model.items) { _, items in api.teaConversations.listViewport.updateOrder(items.map(\.id)) }
    .onChange(of: scenePhase) { _, phase in
      api.teaConversations.listViewport.setActive(phase == .active && active)
      if phase == .active, active { Task { await model.load(reset: true) } }
    }
    .onChange(of: created) { _, post in if let post { model.update(post, insert: true) } }
    .onReceive(NotificationCenter.default.publisher(for: .captroTeaConversationChanged)) { notification in
      guard notification.userInfo?["scope"] as? String == api.presentationScope,
            let post = notification.object as? CaptroTeaConversation else { return }
      model.update(post)
    }
  }
}

private struct CaptroTeaConversationRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let post: CaptroTeaConversation
  @ObservedObject var signal: CaptroTeaNoteSignal
  let signedIn: Bool
  let signIn: () -> Void
  let open: () -> Void
  private var metadataInk: Color { MIRATheme.Color.textSecondary }
  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Layout.avatarGap) {
      Button(action: open) {
        CaptroTeaIdentity(name: post.author.name, photo: post.author.photoURL, size: MIRATheme.Layout.rowAvatar)
      }.buttonStyle(.plain).accessibilityLabel("Open " + post.title)
      VStack(alignment: .leading, spacing: MIRATheme.Space.textGap) {
        Button(action: open) {
        VStack(alignment: .leading, spacing: MIRATheme.Space.textGap) {
        if typeSize.isAccessibilitySize {
          Text(post.title).miraText(.rowTitle).fixedSize(horizontal: false, vertical: true)
          replyCount
        } else {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(post.title).miraText(.rowTitle).fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            replyCount.fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.right").miraText(.metadata).foregroundStyle(metadataInk).accessibilityHidden(true)
          }
        }
        Text(post.body).miraText(.preview).lineSpacing(0).lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("tea.preview." + post.id)
        }
        }.buttonStyle(.plain).accessibilityIdentifier("tea.conversation." + post.id)
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .center, spacing: 8) {
            metadata.fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            interest
          }
          VStack(alignment: .leading, spacing: 0) {
            metadata
            HStack { Spacer(minLength: 0); interest }
          }
        }
        if let error = signal.error { Text(error).miraText(.metadata).foregroundStyle(metadataInk) }

      }.frame(maxWidth: .infinity, alignment: .leading)
    }.foregroundStyle(MIRATheme.Color.textPrimary).padding(.vertical, 18)
      .contentShape(Rectangle())
  }
  private var interest: some View { CaptroTeaInterestControl(model: signal, signedIn: signedIn, signIn: signIn) }
  private var metadata: some View {
    Button(action: open) {
    TeaLinkFlow(spacing: 5, intrinsicWidth: true) {
          HStack(spacing: 4) { Text(post.author.name).miraText(.metadata).foregroundStyle(metadataInk); CaptroVerifiedBadge(verified: post.author.isVerified == true) }
          Text("\u{00B7}").miraText(.metadata).foregroundStyle(metadataInk).accessibilityHidden(true)
          if let date = captroTeaDate(post.createdAt) {
            Text(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
              .miraText(.metadata).foregroundStyle(metadataInk)
          }
          if let borough = post.borough {
            Text("\u{00B7}").miraText(.metadata).foregroundStyle(metadataInk).accessibilityHidden(true)
            Text(borough).miraText(.metadata).foregroundStyle(CaptroTeaStyle.accent)
          }
          CaptroTeaEngagementLabel(model: signal)
        }.padding(.top, 2).accessibilityElement(children: .combine).accessibilityIdentifier("tea.note.identity." + post.id)
    }.buttonStyle(.plain)
  }
  @ViewBuilder private var replyCount: some View {
    if let count = post.replyCount {
      Text("\(count) \(count == 1 ? "reply" : "replies")").miraText(.metadata).foregroundStyle(metadataInk)
    }
  }
}

struct TeaConversationTime: View {
  let value: String
  var body: some View {
    if let date = captroTeaDate(value) {
      Text(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
        .miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary)
    }
  }
}

@MainActor struct CaptroTeaConversationDetail: View {
  let api: MIRAAPIClient
  let viewerID: String?
  let signIn: () -> Void
  @StateObject private var model: CaptroTeaConversationModel
  @StateObject private var signal: CaptroTeaNoteSignal
  @State private var editing = false
  @State private var actionDestination: CaptroTeaNoteDestination?
  @State private var profile: CaptroProfileLink?
  @State private var linkError: String?
  @State private var visible = false
  @State private var actionCovered = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  private var readEligible: Bool {
    visible && scenePhase == .active && model.valid && model.contentReady &&
      !editing && profile == nil && actionDestination == nil && !actionCovered
  }

  init(post: CaptroTeaConversation, api: MIRAAPIClient, viewerID: String?, signIn: @escaping () -> Void) {
    self.api = api; self.viewerID = viewerID; self.signIn = signIn
    _model = StateObject(wrappedValue: api.teaConversations.model(for: post))
    _signal = StateObject(wrappedValue: api.teaConversations.signal(for: post))
  }

  var body: some View {
    List {
      if let post = model.post, model.valid {
        VStack(alignment: .leading, spacing: 8) {
          authorHeader(post)
          Text(post.title).miraText(.sectionTitle).accessibilityAddTraits(.isHeader)
          if let sentences = post.sentences, !sentences.isEmpty {
            ForEach(post.inlineThreads) { group in
              VStack(alignment: .leading, spacing: 8) {
                if group.earlier { Text("Earlier text").miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary) }
                CaptroTeaSelectableText(sentence: group.sentence, reply: target, thread: group,
                  expanded: model.expandedTargets.contains(group.id), toggle: { model.toggleThread(group) })
                if model.expandedTargets.contains(group.id) { sentenceThread(group) }
              }
            }
          } else {
            Text(post.body).miraText(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          }
          HStack {
            CaptroTeaEngagementLabel(model: signal)
            Spacer(minLength: 0)
            CaptroTeaInterestControl(model: signal, signedIn: viewerID != nil, signIn: signIn)
          }
          if let error = signal.error { Text(error).miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary) }
          if post.isAuthor { CaptroTeaInsightsView(model: signal) }
          let links = post.links.compactMap(CaptroTeaLink.init)
          if !links.isEmpty {
            TeaLinkFlow(spacing: 8) {
              ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                HStack(spacing: 7) {
                  if index > 0 { Text("·").foregroundStyle(MIRATheme.Color.textSecondary).accessibilityHidden(true) }
                  Button { open(link) } label: {
                    HStack(spacing: 4) {
                      if let platform = link.platform {
                        Image("Tea" + platform, bundle: .module).renderingMode(.template).resizable().scaledToFit()
                          .frame(width: 11, height: 11).accessibilityHidden(true)
                      } else { Image(systemName: "link").font(.system(size: 11)).accessibilityHidden(true) }
                      Text(link.hostname).miraText(.preview).underline().fixedSize(horizontal: false, vertical: true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                  }.buttonStyle(.plain).foregroundStyle(CaptroTeaStyle.accent)
                    .accessibilityLabel("Open \(link.hostname)\(link.profile == nil ? " in browser" : " in Captro")")
                    .accessibilityIdentifier("tea.link." + link.hostname)
                }
              }
            }
          }
          if let borough = post.borough { Text(borough).font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary) }
          if post.primaryAction != nil || post.canManageApplications == true {
            CaptroTeaNoteActionView(note: post, api: api, viewerID: viewerID, signIn: signIn, coverChanged: { actionCovered = $0 }) { actionDestination = $0 }
          }
          if let linkError { Text(linkError).font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary) }
        }.background(CaptroFeedViewportMarker(owner: model.viewport, postID: "caption", feed: "tea:" + model.id).allowsHitTesting(false))
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
          .listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
        if let error = model.authorError {
          HStack { Text(error).font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary); Button("Retry profile") { Task { await model.loadAuthor() } }.frame(minHeight: 44) }
            .listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
        }
        HStack {
          VStack(alignment: .leading, spacing: MIRATheme.Space.textGap) {
            Text(post.replyCount.map { "Replies (\($0))" } ?? "Replies").miraText(.rowTitle)
            if !(post.replyTargets ?? []).isEmpty { Text("General replies").font(.caption).foregroundStyle(MIRATheme.Color.textSecondary) }
            if model.nextCursor != nil {
              Text("\(model.replies.filter { $0.target == nil }.count) general replies loaded").font(.caption).foregroundStyle(MIRATheme.Color.textSecondary)
            }
          }
          Spacer()
          Button {
            if viewerID == nil { signIn() } else { Task { await model.follow() } }
          } label: { Image(systemName: post.following ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44) }
            .buttonStyle(.plain).disabled(model.busy)
            .accessibilityLabel(post.following ? "Unfollow discussion" : "Follow discussion")
            .accessibilityIdentifier("tea.conversation.follow")
        }.listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
        TeaReplyGroups(replies: model.replies.filter { $0.target == nil })
          .background(CaptroFeedViewportMarker(owner: model.viewport, postID: "general", feed: "tea:" + model.id).allowsHitTesting(false))
          .listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
        if model.loadingReplies { ProgressView("Loading replies").listRowSeparator(.hidden) }
        if model.nextCursor != nil {
          Button("More replies") { Task { await model.loadReplies(reset: false) } }.frame(minHeight: 44).disabled(model.loadingReplies)
        }
        if let error = model.replyError {
          VStack(alignment: .leading) {
            Text(error).font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary)
            Button("Retry") { Task {
              if model.replySubmissionFailed { await model.sendReply() } else { await model.loadReplies(reset: model.nextCursor == nil, force: true) }
            } }.frame(minHeight: 44).disabled(model.busy)
          }.listRowSeparator(.hidden)
        }
      }
      if let error = model.error {
        VStack(alignment: .leading) {
          Text(error).font(.subheadline).foregroundStyle(MIRATheme.Color.textSecondary)
          Button("Retry") { Task { await model.load(force: true) } }.frame(minHeight: 44)
        }.listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
      }
      if model.loading, model.post == nil {
        ProgressView("Loading post").listRowSeparator(.hidden).listRowBackground(MIRATheme.Color.appBackground)
      }
    }.listStyle(.plain).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
      .navigationTitle("").navigationBarTitleDisplayMode(.inline).miraNavigationSurface()
      .accessibilityIdentifier("tea.conversation.detail")
      .navigationDestination(item: $actionDestination) { destination in
        CaptroTeaNoteDestinationView(destination: destination, api: api, viewerID: viewerID, signIn: signIn)
      }
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
              VStack(alignment: .leading, spacing: MIRATheme.Space.textGap) {
                Text("Replying to this line").font(.caption).foregroundStyle(MIRATheme.Color.textSecondary).accessibilityIdentifier("tea.reply.target")
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
                .miraText(.body).padding(.horizontal, 14).padding(.vertical, 11).background(CaptroTeaStyle.composerFill, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("tea.reply.input")
              Button { Task {
                await model.sendReply()
                if model.post?.isAuthor == true, model.replyError == nil { await signal.loadInsights(force: true) }
              } } label: {
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
      .task(id: readEligible) {
        guard readEligible, let post = model.post else { return }
        await Task.yield() // Start after the loaded content's render, never its loader.
        guard !Task.isCancelled else { return }
        await signal.qualifyRead(isAuthor: post.isAuthor, authenticated: viewerID != nil)
      }
      .toolbar(.hidden, for: .tabBar)
      .onAppear { visible = true; model.collapseThreads(); model.viewport.setActive(true) }
      .onDisappear { visible = false; model.collapseThreads(); model.viewport.setActive(false) }
      .refreshable {
        await model.load(force: true)
        if model.post?.isAuthor == true { await signal.loadInsights(force: true) }
      }
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
        VStack(alignment: .leading, spacing: MIRATheme.Space.textGap) {
          HStack(spacing: 4) { Text(post.author.name).miraText(.rowTitle); CaptroVerifiedBadge(verified: post.author.isVerified == true) }
          TeaLinkFlow(spacing: 5) {
            Text("@" + post.author.username).miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary)
            Text("\u{00B7}").miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary).accessibilityHidden(true)
            TeaConversationTime(value: post.createdAt)
          }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityLabel("Open profile for " + post.author.name)
        .accessibilityIdentifier("tea.author.profile")

    }.foregroundStyle(MIRATheme.Color.textPrimary).padding(.bottom, 4)
  }
  private func target(_ sentence: CaptroTeaReplyTarget) {
    if viewerID == nil { signIn() } else { model.selectTarget(sentence) }
  }
  private func sentenceThread(_ group: CaptroTeaInlineThread) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(model.threads[group.id] ?? []) { reply in
        VStack(alignment: .leading, spacing: 4) {
          if let quote = reply.target?.quote { CaptroTeaQuote(text: quote) }
          TeaReplyGroups(replies: [reply])
        }
      }
      if model.loadingThreads.contains(group.id) { ProgressView("Loading replies") }
      if let error = model.threadErrors[group.id] {
        Text(error).miraText(.metadata)
        Button("Retry replies") { Task { await model.loadThread(group, reset: true) } }.frame(minHeight: 44)
      }
      if model.threadCursors[group.id] != nil {
        Button("Load more") { Task { await model.loadThread(group) } }.frame(minHeight: 44)
          .disabled(model.loadingThreads.contains(group.id)).accessibilityIdentifier("tea.thread.more." + group.id)
      }
    }.padding(.leading, 12)
      .overlay(alignment: .leading) { Rectangle().fill(CaptroTeaStyle.accent.opacity(0.25)).frame(width: 1) }
      .accessibilityIdentifier("tea.thread.expanded." + group.id)
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
          CaptroTeaIdentity(name: group.replies[0].author.name, photo: group.replies[0].author.photoURL, size: 40)
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(group.replies.enumerated()), id: \.element.id) { index, reply in
              VStack(alignment: .leading, spacing: 4) {
                TeaLinkFlow(spacing: 5) {
                  if index == 0 {
                    HStack(spacing: 4) { Text(reply.author.name).miraText(.rowTitle); CaptroVerifiedBadge(verified: reply.author.isVerified == true) }
                    Text("@" + reply.author.username).miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary)
                    Text("\u{00B7}").miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary).accessibilityHidden(true)
                  }
                  TeaConversationTime(value: reply.createdAt)
                }
                Text(reply.body).miraText(.body).fixedSize(horizontal: false, vertical: true)
              }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("tea.reply." + reply.id)
            }
          }
        }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .bottom) { MIRAHairline(color: CaptroTeaStyle.separator) }
      }
    }
  }
}

/// Wrap whole link controls instead of squeezing them into one horizontal line.
struct TeaLinkFlow: Layout {
  let spacing: CGFloat
  var intrinsicWidth = false
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let ideal = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width } + CGFloat(max(0, subviews.count - 1)) * spacing
    return arrange(width: proposal.width ?? (intrinsicWidth ? ideal : 320), subviews: subviews).size
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
  @State private var submitted: CaptroTeaNotePayload?
  @State private var borough: String
  @State private var action: CaptroTeaNoteAction?
  @State private var editingAction = false

  init(api: MIRAAPIClient, editing: CaptroTeaConversation? = nil, saved: @escaping (CaptroTeaConversation) -> Void) {
    self.api = api; self.editing = editing; self.saved = saved
    _title = State(initialValue: editing?.title ?? "")
    _bodyText = State(initialValue: editing?.body ?? "")
    _links = State(initialValue: editing?.links ?? [])
    _borough = State(initialValue: editing?.borough ?? "")
    _action = State(initialValue: editing?.primaryAction?.input)
  }
  private var valid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 160 &&
    !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.count <= 8000 &&
    links.allSatisfy { CaptroTeaLink($0) != nil } && (action?.valid ?? true)
  }
  var body: some View {
    NavigationStack {
      Form {
        Group {
        TextField("Title", text: $title, axis: .vertical).accessibilityIdentifier("tea.compose.title")
        TextField("Write a Note…", text: $bodyText, axis: .vertical).lineLimit(5...14).accessibilityIdentifier("tea.compose.body")
        Section {
          Picker("Borough (optional)", selection: $borough) {
            Text("Not specified").tag("")
            ForEach(["Brooklyn", "Queens", "Manhattan", "Bronx", "Staten Island"], id: \.self) { Text($0).tag($0) }
          }.accessibilityIdentifier("tea.compose.borough")
          Button(action == nil ? "Add action" : "Edit action") { editingAction = true }
            .accessibilityIdentifier("tea.compose.action")
          if let action {
            Text(action.label).font(.subheadline.weight(.semibold)).foregroundStyle(CaptroTeaStyle.accent)
            if let link = action.url.flatMap(CaptroTeaLink.init) { Text(link.hostname).font(.caption).foregroundStyle(MIRATheme.Color.textSecondary) }
          }
        } footer: { Text("Optional. A borough is shown only when you choose one. Add one next step if your Note needs it.") }
        Section {
          ForEach(links.indices, id: \.self) { index in
            HStack {
              TextField("https://", text: $links[index]).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Link \(index + 1)").accessibilityIdentifier("tea.compose.link.\(index)")
              Button { links.remove(at: index) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Remove link \(index + 1)")
            }
          }
          if links.count < 3 {
            Button { links.append("") } label: {
              Text("Add link").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(CaptroTeaStyle.accent)
          }
        } footer: { Text("Optional. Up to three HTTPS links. Only you can edit the links on your post.") }
        }.disabled(saving || submitted != nil)
        if let error { Text(error).font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary) }
      }.disabled(saving).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
        .navigationTitle(editing == nil ? "New Note" : "Edit Note").navigationBarTitleDisplayMode(.inline).miraNavigationSurface()
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
          ToolbarItem(placement: .confirmationAction) {
            Button(saving ? "Saving…" : submitted != nil ? "Retry" : editing == nil ? "Post" : "Save") { Task { await save() } }
              .disabled(!valid || saving).accessibilityIdentifier("tea.compose.save")
          }
        }.interactiveDismissDisabled(saving)
        .sheet(isPresented: $editingAction) { CaptroTeaNoteActionEditor(api: api, action: action) { action = $0 } }
    }
  }
  @MainActor private func save() async {
    guard valid, !saving else { return }
    saving = true; error = nil; defer { saving = false }
    let owner = api.presentationScope
    // Retain a request's exact payload after an ambiguous response; subsequent
    // retry resolves that operation instead of silently creating another post.
    let payload = submitted ?? CaptroTeaNotePayload(title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
      links: links.compactMap { CaptroTeaLink($0)?.url.absoluteString }, requestID: editing == nil ? requestID : nil, version: editing?.version, borough: borough.isEmpty ? nil : borough, primaryAction: action)
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
