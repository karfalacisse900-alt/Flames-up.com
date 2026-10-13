import SwiftUI

struct CaptroFavoritePicker: View {
  let postID: String
  let api: MIRAAPIClient
  @ObservedObject private var store: CaptroFavoritesStore
  @Environment(\.dismiss) private var dismiss
  @State private var original: CaptroFavoriteState?
  @State private var selected: Set<String> = []
  @State private var loading = true
  @State private var saving = false
  @State private var error: String?
  @State private var naming = false
  @State private var name = ""
  init(postID: String, api: MIRAAPIClient) {
    self.postID=postID; self.api=api; _store=ObservedObject(wrappedValue: api.favorites)
  }
  var body: some View {
    NavigationStack {
      List {
        Text("Private · Only you can see your Favorites.").font(.footnote).foregroundStyle(.secondary)
        if loading { ProgressView("Loading collections…") }
        if let error { Text(error).foregroundStyle(.red); Button("Retry", action: load) }
        ForEach(store.collections) { collection in
          Button {
            if selected.contains(collection.id) { selected.remove(collection.id) }
            else if selected.count < 20 { selected.insert(collection.id) }
          } label: {
            HStack {
              FavoriteCollectionPreview(collection: collection)
              Text(collection.name).foregroundStyle(MIRATheme.Color.textPrimary)
              Spacer()
              Image(systemName: selected.contains(collection.id) ? "checkmark.circle.fill" : "circle")
            }.frame(minHeight: 44)
          }
          .accessibilityLabel(collection.name)
          .accessibilityValue(selected.contains(collection.id) ? "Selected" : "Not selected")
          .disabled(loading || saving)
        }
        Button("New collection") { name=""; naming=true }.disabled(loading || saving)
      }
      .scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
      .navigationTitle("Save to collections").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            guard let original else { return }; saving=true
            Task {
              if await store.organize(previous: original, collectionIDs: selected) { dismiss() }
              else { error="Couldn’t save your choices. Cancel or reload to try again." }
              saving=false
            }
          }.disabled(loading || saving || original == nil)
        }
      }
      .overlay(alignment: .top) { CaptroFavoriteNotice(store: store) }
      .alert("New collection", isPresented: $naming) {
        TextField("Name", text: $name)
        Button("Cancel", role: .cancel) {}
        Button("Create") { Task {
          do { try await store.manageCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
          catch { self.error=error.localizedDescription }
        } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count>80)
      } message: { Text("Use up to 80 characters. Only you can see this collection.") }
      .task { load() }
      .onChange(of: store.accountID) { _, _ in dismiss() }
      .interactiveDismissDisabled(saving)
    }
  }
  private func load() {
    loading=true; error=nil
    Task {
      do {
        _ = try await store.page()
        let state = try await store.loadState(postID: postID)
        original=state; selected=Set(state.collectionIds)
      } catch { self.error=error.localizedDescription }
      loading=false
    }
  }
}

private struct FavoriteCollectionPreview: View {
  let collection: CaptroFavoriteCollection
  var body: some View {
    Group {
      if let url=collection.previews?.first?.favoriteThumbnailURL {
        RemoteMediaView(url: url, isVideo: false)
      } else { Image(systemName: "square.stack").foregroundStyle(.secondary) }
    }.frame(width: 40,height:40).clipped().background(MIRATheme.Color.surfaceSoft).accessibilityHidden(true)
  }
}

struct CaptroFavoritesView: View {
  let api: MIRAAPIClient
  @ObservedObject private var store: CaptroFavoritesStore
  @State private var collectionID: String?
  @State private var entries: [CaptroFavoriteEntry] = []
  @State private var loading = false
  @State private var nextOffset = 0
  @State private var hasMore = false
  @State private var error: String?
  @State private var request = UUID()
  @State private var name = ""
  @State private var editingID: String?
  @State private var naming = false
  @State private var deleting: CaptroFavoriteCollection?
  @State private var managing = false
  init(api: MIRAAPIClient) { self.api=api; _store=ObservedObject(wrappedValue: api.favorites) }
  var body: some View {
    List {
      Section {
        Button { collectionID=nil } label: { selectionRow("All saved", selected: collectionID == nil) }
        ForEach(store.collections) { collection in
          HStack {
            Button { collectionID=collection.id } label: {
              HStack { FavoriteCollectionPreview(collection: collection); selectionRow(collection.name, selected: collectionID == collection.id) }
            }
            Menu {
              Button("Rename") { editingID=collection.id; name=collection.name; naming=true }
              Button("Delete collection",role:.destructive) { deleting=collection }
            } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("Manage \(collection.name)")
          }
        }
        Button("New collection") { editingID=nil; name=""; naming=true }
      } header: { Text("Private · Only you") }
      if let error { Section { Text(error).foregroundStyle(.red); Button("Retry") { Task { await load(reset:true) } } } }
      Section(collectionID == nil ? "All saved" : store.collections.first(where:{$0.id==collectionID})?.name ?? "Collection") {
        if loading && entries.isEmpty { ProgressView("Loading Favorites…") }
        else if entries.isEmpty && error == nil { Text("Nothing saved here yet. Tap a post’s star to save it; hold to organize.").foregroundStyle(.secondary) }
        ForEach(entries) { entry in
          if let post=entry.post {
            NavigationLink(destination: PostDetailNativeView(post:post,api:api).miraHideTabBarOnAppear()) {
              HStack(spacing:12) {
                if let url=post.favoriteThumbnailURL {
                  RemoteMediaView(url:url,isVideo:false).frame(width:64,height:64).clipped()
                } else { Image(systemName:"doc.text").frame(width:64,height:64) }
                VStack(alignment:.leading,spacing:4) {
                  Text(post.titleText).lineLimit(2)
                  Text(post.authorDisplayName).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          } else {
            HStack { Text("Post unavailable").foregroundStyle(.secondary); Spacer()
              Button("Remove") { Task {
                do {
                  let state=try await store.loadState(postID:entry.id)
                  await store.remove(state:state)
                } catch { self.error=error.localizedDescription }
              } }
            }
          }
        }
        if hasMore { Button(loading ? "Loading…" : "Load more") { Task { await load(reset:false) } }.disabled(loading) }
      }
    }
    .disabled(managing).scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
    .navigationTitle("Favorites").navigationBarTitleDisplayMode(.inline).miraHideTabBarOnAppear()
    .overlay(alignment:.top) { CaptroFavoriteNotice(store:store) }
    .task(id:collectionID) { await load(reset:true) }
    .onChange(of:store.changeVersion) { _,_ in Task { await load(reset:true) } }
    .onChange(of:store.accountID) { _,_ in request=UUID(); entries=[]; collectionID=nil }
    .refreshable { await load(reset:true) }
    .alert(editingID == nil ? "New collection" : "Rename collection",isPresented:$naming) {
      TextField("Name",text:$name)
      Button("Cancel",role:.cancel) {}
      Button("Save") { manage(id:editingID,name:name.trimmingCharacters(in:.whitespacesAndNewlines)) }
        .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>80)
    } message: { Text("Private to you. Up to 80 characters.") }
    .confirmationDialog("Delete collection?",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {
      Button("Delete collection",role:.destructive) { if let id=deleting?.id { if collectionID==id {collectionID=nil}; manage(id:id,name:nil) }; deleting=nil }
    } message: { Text("Its posts will stay in All saved. Only the collection will be deleted.") }
  }
  private func selectionRow(_ title:String,selected:Bool) -> some View {
    HStack { Text(title).foregroundStyle(MIRATheme.Color.textPrimary); Spacer(); if selected {Image(systemName:"checkmark")} }.frame(minHeight:44)
  }
  private func manage(id:String?,name:String?) {
    managing=true
    Task { do {try await store.manageCollection(id:id,name:name)} catch {self.error=error.localizedDescription}; managing=false }
  }
  private func load(reset:Bool) async {
    if loading && !reset {return}
    let token=UUID(); request=token; let selected=collectionID
    loading=true; error=nil
    do {
      let page=try await store.page(collectionID:selected,offset:reset ? 0 : nextOffset)
      guard request==token,!Task.isCancelled else{return}
      if reset { entries=page.entries } else { let ids=Set(entries.map(\.id)); entries += page.entries.filter{!ids.contains($0.id)} }
      hasMore=page.hasMore; nextOffset=page.nextOffset
    } catch {guard request==token else{return}; self.error=error.localizedDescription}
    if request==token {loading=false}
  }
}

private extension MIRAPost {
  // A missing video thumbnail must not download/decode the original movie
  // through the image cache just to draw a small collection preview.
  var favoriteThumbnailURL: String? {
    thumbnailMediaURLs.first(where: { !$0.isVideoURL }) ?? feedMediaURLs.first(where: { !$0.isVideoURL })
  }
}
