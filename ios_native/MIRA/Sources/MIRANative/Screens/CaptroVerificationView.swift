import SwiftUI

struct CaptroBadgeApplication: Decodable {
  let status: String
  let displayName: String
  let reason: String
  let links: [String]
  let reviewerMessage: String
  let version: Int
}
private struct CaptroBadgeState: Decodable {
  let application: CaptroBadgeApplication?
  let isVerified: Bool
}
private struct CaptroBadgeRequest: Encodable {
  let id: String
  let version: Int
  let displayName, reason: String
  let links: [String]
}

@MainActor struct CaptroVerificationView: View {
  let api: MIRAAPIClient
  @State private var state: CaptroBadgeState?
  @State private var name = ""
  @State private var reason = ""
  @State private var links = ""
  @State private var busy = false
  @State private var error: String?
  @State private var confirmed = false
  @State private var pending: CaptroBadgeRequest?
  private var editable: Bool {
    guard let state else { return false }
    return !state.isVerified && !["under_review","approved"].contains(state.application?.status ?? "")
  }
  private var parsedLinks: [String] { links.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
  private var valid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 120 &&
    reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 && reason.count <= 1500 &&
    parsedLinks.count <= 3 && parsedLinks.allSatisfy { CaptroTeaLink($0) != nil }
  }
  var body: some View {
    Form {
      Section {
        Text("Apply for a verified account badge. Captro reviews each application. Approval does not enable payments or professional features.")
          .font(.subheadline)
        Text("Your application and review messages are private. Only the approved badge is public on your profile, posts and replies.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let state {
        Section("Status") {
          HStack {
            Text(state.isVerified ? "Approved" : statusName(state.application?.status))
            CaptroVerifiedBadge(verified: state.isVerified)
          }
          if let message = state.application?.reviewerMessage, !message.isEmpty { Text(message).font(.subheadline) }
        }
        if editable {
          Section("Application") {
            TextField("Public name or business name", text: $name)
            TextField("Tell reviewers who you are and why this account should be verified", text: $reason, axis: .vertical).lineLimit(3...8)
            TextField("Supporting HTTPS links (optional, one per line)", text: $links, axis: .vertical)
              .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4)
            Text("Up to three links. Do not send passwords, banking information or identity documents here.").font(.footnote).foregroundStyle(.secondary)
          }.disabled(busy || pending != nil)
          Button(pending == nil ? "Submit application" : "Retry submission") { Task { await submit() } }
            .disabled(busy || (!valid && pending == nil))
        }
      } else if busy { ProgressView("Loading verification") }
      if confirmed { Text("Application received. Your account stays unchanged while it is reviewed.").font(.subheadline) }
      if let error {
        Section {
          Text(error).foregroundStyle(.secondary)
          if pending == nil { Button("Retry") { Task { await load() } }.disabled(busy) }
        }
      }
    }.navigationTitle("Account verification").navigationBarTitleDisplayMode(.inline)
      .scrollContentBackground(.hidden).background(MIRATheme.Color.appBackground)
      .task { await load() }
      .refreshable { await load() }
  }
  private func statusName(_ status: String?) -> String {
    switch status {
    case "under_review": return "Under review"
    case "needs_changes": return "Needs changes"
    case "declined": return "Declined"
    case "revoked": return "Badge removed"
    case "approved": return "Approved"
    default: return "Not submitted"
    }
  }
  private func load() async {
    guard !busy else { return }
    busy = true; error = nil
    let scope = api.presentationScope
    defer { busy = false }
    do {
      let result: CaptroBadgeState = try await api.getFresh("/verification/me")
      guard scope == api.presentationScope, !Task.isCancelled else { return }
      if state == nil, let application = result.application {
        name = application.displayName; reason = application.reason; links = application.links.joined(separator: "\n")
      }
      state = result
    } catch { self.error = "Could not load verification. Try again." }
  }
  private func submit() async {
    guard !busy, editable, valid || pending != nil else { return }
    if pending == nil { pending = .init(id: UUID().uuidString, version: state?.application?.version ?? 0, displayName: name, reason: reason, links: parsedLinks) }
    guard let request = pending else { return }
    busy = true; error = nil
    let scope = api.presentationScope
    do {
      struct Result: Decodable { let ok: Bool }
      let result: Result = try await api.post("/verification/apply", body: request)
      guard scope == api.presentationScope else { busy = false; return }
      guard result.ok else { throw MIRAAPIError.emptyResponse }
      pending = nil; confirmed = true; busy = false
      await load()
    } catch {
      if case MIRAAPIError.server(let status, _, let detail) = error, [400,403,409].contains(status) {
        pending = nil; self.error = detail ?? "Refresh your application and try again."
      } else { self.error = "Submission was not confirmed. Retry safely to check or send the same application." }
      busy = false
    }
  }
}
