import SwiftUI

private extension Notification.Name {
  static let captroPostResponseUpdated = Notification.Name("captro.postResponse.updated")
}

private struct CaptroPostResponseBody: Encodable {
  let selectedOption: String?
  let clientOperationId: String
}

private struct CaptroRespondent: Decodable, Identifiable {
  let id: String
  let username: String?
  let profileImage: String?
}

struct CaptroPostResponseView: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let onReply: () -> Void
  var canRespond = true

  @State private var current: CaptroPostResponse?
  @State private var pendingOperation: String?
  @State private var errorMessage: String?
  @State private var peopleOption = ""
  @State private var showsPeople = false

  init(post: MIRAPost, api: MIRAAPIClient, canRespond: Bool = true, onReply: @escaping () -> Void) {
    self.post = post
    self.api = api
    self.canRespond = canRespond
    self.onReply = onReply
    _current = State(initialValue: post.response)
  }

  var body: some View {
    Group {
      if let response = current {
        VStack(alignment: .leading, spacing: 8) {
          switch response.type {
          case "yes_no":
            HStack(spacing: 8) {
              choice("Yes", response: response)
              choice("No", response: response)
            }
          case "interested":
            choice("Interested", label: "I'm interested", response: response)
          case "going":
            choice("Going", response: response)
          case "poll":
            VStack(spacing: 7) {
              ForEach(response.options, id: \.self) { option in
                choice(option, response: response)
              }
            }
          case "question":
            if canRespond {
              Button("Reply", action: onReply)
                .buttonStyle(.bordered)
                .tint(MIRATheme.Color.forest)
                .frame(minHeight: 44)
            }
          default:
            EmptyView()
          }

          if response.type == "question" {
            Text("\(post.commentsCount ?? 0) replies")
              .font(.system(size: 13))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          } else if response.type == "interested" || response.type == "going" {
            Button {
              peopleOption = response.options.first ?? ""
              showsPeople = true
            } label: {
              Text("\(response.totalCount) \(response.type == "going" ? "going" : "interested")")
                .font(.system(size: 13))
                .foregroundStyle(MIRATheme.Color.textSecondary)
                .frame(minHeight: 36, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(response.totalCount == 0 || !canRespond)
          } else {
            Text("\(response.totalCount) \(response.type == "poll" ? "votes" : "responses")")
              .font(.system(size: 13))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 13))
              .foregroundStyle(.red)
              .accessibilityAddTraits(.updatesFrequently)
          }
          if !canRespond {
            Text(response.type == "question" ? "Sign in to reply" : "Sign in to respond")
              .font(.system(size: 13))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: post.response) { _, updated in
          if pendingOperation == nil { current = updated }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captroPostResponseUpdated)) { event in
          guard event.object as? String == post.id,
                let updated = event.userInfo?["response"] as? CaptroPostResponse,
                pendingOperation == nil else { return }
          current = updated
        }
        .sheet(isPresented: $showsPeople) {
          CaptroRespondentsSheet(postID: post.id, option: peopleOption, api: api)
        }
      }
    }
  }

  private func choice(_ option: String, label: String? = nil, response: CaptroPostResponse) -> some View {
    let selected = response.viewerOption == option
    let count = response.counts[option] ?? 0
    return Button {
      choose(selected ? nil : option)
    } label: {
      HStack(spacing: 6) {
        Text(label ?? option).lineLimit(2)
        Spacer(minLength: 0)
        if response.viewerOption != nil && (response.type == "yes_no" || response.type == "poll") {
          let percent = response.totalCount > 0 ? Int((Double(count) / Double(response.totalCount) * 100).rounded()) : 0
          Text("\(percent)%").monospacedDigit()
        }
        if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
      }
      .font(.system(size: 14, weight: selected ? .semibold : .medium))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(selected ? MIRATheme.Color.forest.opacity(0.12) : MIRATheme.Color.surfaceSoft,
                  in: RoundedRectangle(cornerRadius: 9))
      .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(
        selected ? MIRATheme.Color.forest : MIRATheme.Color.hairline, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .disabled(pendingOperation != nil || !canRespond)
    .accessibilityLabel("\(label ?? option), \(count) responses\(selected ? ", selected" : "")")
  }

  private func choose(_ option: String?) {
    guard pendingOperation == nil, let previous = current else { return }
    let operationID = UUID().uuidString
    pendingOperation = operationID
    errorMessage = nil
    var counts = previous.counts
    if let old = previous.viewerOption { counts[old] = max(0, (counts[old] ?? 0) - 1) }
    if let option { counts[option] = (counts[option] ?? 0) + 1 }
    current = CaptroPostResponse(type: previous.type, options: previous.options, counts: counts,
      totalCount: counts.values.reduce(0, +), viewerOption: option)

    Task { @MainActor in
      do {
        let confirmed: CaptroPostResponse = try await api.post("/posts/\(post.id)/responses",
          body: CaptroPostResponseBody(selectedOption: option, clientOperationId: operationID))
        guard pendingOperation == operationID else { return }
        current = confirmed
        pendingOperation = nil
        NotificationCenter.default.post(name: .captroPostResponseUpdated, object: post.id,
          userInfo: ["response": confirmed])
      } catch {
        guard pendingOperation == operationID else { return }
        current = previous
        pendingOperation = nil
        errorMessage = "Could not save your response. Try again."
      }
    }
  }
}

private struct CaptroRespondentsSheet: View {
  let postID: String
  let option: String
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var people: [CaptroRespondent] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Group {
        if isLoading && people.isEmpty { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if let errorMessage {
          Label(errorMessage, systemImage: "wifi.exclamationmark")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        else if people.isEmpty { ContentUnavailableView("No responses yet", systemImage: "person.2") }
        else {
          List(people) { person in
            HStack(spacing: 10) {
              RemoteAvatar(url: person.profileImage, size: 36)
              Text("@\(person.username ?? "member")")
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle(option == "Going" ? "Going" : "Interested")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
    .task {
      do {
        let encoded = option.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? option
        people = try await api.get("/posts/\(postID)/responses/people?option=\(encoded)")
      } catch {
        errorMessage = "Could not load responses."
      }
      isLoading = false
    }
  }
}
