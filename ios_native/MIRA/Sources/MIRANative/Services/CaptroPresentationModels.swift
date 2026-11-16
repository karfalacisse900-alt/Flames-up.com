import Foundation

/// Short-lived presentation reuse on the existing API client. It is never an
/// authorization cache. Scope changes synchronously clear retained models and
/// their drafts; every server result still passes the model's scope check.
@MainActor final class CaptroPresentationModels {
  private unowned let api: MIRAAPIClient
  private var scope = ""
  private var rooms: [ConversationNativeKind: ConversationNativeModel] = [:]
  private var roomOrder: [ConversationNativeKind] = []
  private var retainedDrafts: [ConversationNativeKind: String] = [:]
  private var draftOrder: [ConversationNativeKind] = []
  private var profiles: [String: UserProfileNativeModel] = [:]
  private var profileOrder: [String] = []
  init(api: MIRAAPIClient) { self.api = api }
  private func synchronize() {
    guard scope != api.presentationScope else { return }
    invalidate(); scope = api.presentationScope
  }
  func room(_ kind: ConversationNativeKind, userID: String) -> ConversationNativeModel {
    synchronize()
    roomOrder.removeAll { $0 == kind }; roomOrder.append(kind)
    if let model = rooms[kind], model.currentUserId == userID { return model }
    let model = ConversationNativeModel(kind: kind, api: api, currentUserId: userID)
    model.draft = retainedDrafts.removeValue(forKey: kind) ?? ""
    draftOrder.removeAll { $0 == kind }
    rooms[kind] = model
    // Bound heavy message models separately from small, account-private drafts.
    // Sending models stay alive for acknowledgment even when removed from reuse.
    while rooms.count > 12, let old = roomOrder.first(where: { $0 != kind }) {
      if let evicted = rooms.removeValue(forKey: old), !evicted.draft.isEmpty {
        retainedDrafts[old] = evicted.draft; draftOrder.append(old)
      }
      roomOrder.removeAll { $0 == old }
    }
    while draftOrder.count > 64 { retainedDrafts.removeValue(forKey: draftOrder.removeFirst()) }
    return model
  }
  func profile(_ id: String) -> UserProfileNativeModel {
    synchronize()
    profileOrder.removeAll { $0 == id }; profileOrder.append(id)
    if let model = profiles[id] { return model }
    let model = UserProfileNativeModel(userId: id, api: api)
    profiles[id] = model
    while profileOrder.count > 12 { profiles.removeValue(forKey: profileOrder.removeFirst())?.clearPresentation() }
    return model
  }
  func invalidate() {
    rooms.values.forEach { $0.clearPresentation() }
    profiles.values.forEach { $0.clearPresentation() }
    rooms = [:]; roomOrder = []; profiles = [:]; profileOrder = []
    retainedDrafts = [:]; draftOrder = []
  }
}
