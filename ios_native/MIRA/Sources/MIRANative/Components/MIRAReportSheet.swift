import SwiftUI
import UIKit

public struct MIRAReportTarget: Identifiable, Equatable {
  public let targetType: String
  public let targetId: String
  public let ownerUserId: String?
  public let title: String
  public let subtitle: String?

  public var id: String { "\(targetType):\(targetId)" }

  public init(targetType: String, targetId: String, ownerUserId: String? = nil, title: String, subtitle: String? = nil) {
    self.targetType = targetType
    self.targetId = targetId
    self.ownerUserId = ownerUserId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? ownerUserId : nil
    self.title = title
    self.subtitle = subtitle
  }
}

public struct MIRAReportResult: Equatable {
  public let reportId: String?
  public let duplicate: Bool
  public let blocked: Bool
  public let hidden: Bool
}

private struct MIRAReportSubmitBody: Encodable {
  let targetType: String
  let targetId: String
  let reason: String
  let details: String?
  let blockUser: Bool
  let hideContent: Bool
}

private struct MIRAReportSubmitResponse: Decodable {
  let id: String?
  let reported: Bool?
  let duplicate: Bool?
  let blocked: Bool?
  let hidden: Bool?
}

private struct MIRAReportReasonChoice: Identifiable, Hashable {
  let id: String
  let title: String
  let systemImage: String
}

private let miraReportReasons: [MIRAReportReasonChoice] = [
  .init(id: "harassment_or_bullying", title: "Harassment or bullying", systemImage: "person.crop.circle.badge.exclamationmark"),
  .init(id: "hate_speech", title: "Hate speech", systemImage: "exclamationmark.bubble"),
  .init(id: "threats_or_violence", title: "Threats or violence", systemImage: "bolt.trianglebadge.exclamationmark"),
  .init(id: "doxxing_or_private_information", title: "Doxxing or private information", systemImage: "lock.trianglebadge.exclamationmark"),
  .init(id: "spam_or_scam", title: "Spam or scam", systemImage: "shield.lefthalf.filled.badge.checkmark"),
  .init(id: "impersonation", title: "Impersonation", systemImage: "person.text.rectangle"),
  .init(id: "stolen_content_or_copyright", title: "Stolen content or copyright", systemImage: "doc.on.doc"),
  .init(id: "sexual_content_or_exploitation", title: "Sexual content or exploitation", systemImage: "exclamationmark.shield"),
  .init(id: "illegal_or_dangerous_activity", title: "Illegal or dangerous activity", systemImage: "flame"),
  .init(id: "self_harm_concern", title: "Self-harm concern", systemImage: "heart.text.square"),
  .init(id: "false_or_misleading_content", title: "False or misleading content", systemImage: "questionmark.diamond"),
  .init(id: "dont_want_to_see", title: "I don't want to see this", systemImage: "eye.slash"),
  .init(id: "other", title: "Other", systemImage: "ellipsis.circle")
]

public struct MIRAReportSheet: View {
  private enum Step {
    case reasons
    case details
    case confirmation
  }

  let target: MIRAReportTarget
  let api: MIRAAPIClient
  let onSubmitted: (MIRAReportResult) -> Void
  let onClose: () -> Void

  @State private var step: Step = .reasons
  @State private var selectedReason: MIRAReportReasonChoice?
  @State private var details = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var lastResult: MIRAReportResult?
  @FocusState private var detailsFocused: Bool

  public init(
    target: MIRAReportTarget,
    api: MIRAAPIClient,
    onSubmitted: @escaping (MIRAReportResult) -> Void,
    onClose: @escaping () -> Void
  ) {
    self.target = target
    self.api = api
    self.onSubmitted = onSubmitted
    self.onClose = onClose
  }

  public var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          targetPreview

          switch step {
          case .reasons:
            reasonList
          case .details:
            detailsStep
          case .confirmation:
            confirmationStep
          }
        }
        .padding(.horizontal, MIRATheme.Space.lg)
        .padding(.top, MIRATheme.Space.lg)
        .padding(.bottom, MIRATheme.Space.xxl)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      footer
    }
    .background(MIRATheme.Color.surface)
  }

  private var header: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.22))
        .frame(width: 42, height: 5)
        .padding(.top, 10)

      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(headerTitle)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text(headerSubtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(2)
        }
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .frame(width: 34, height: 34)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
      }
      .padding(.horizontal, MIRATheme.Space.lg)
      .padding(.bottom, MIRATheme.Space.sm)
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var targetPreview: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: iconForTarget)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 36, height: 36)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(target.title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
        if let subtitle = target.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surfaceSoft)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var reasonList: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      ForEach(miraReportReasons) { reason in
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          selectedReason = reason
          withAnimation(.easeInOut(duration: 0.18)) {
            step = .details
          }
        } label: {
          HStack(spacing: MIRATheme.Space.sm) {
            Image(systemName: reason.systemImage)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .frame(width: 28, height: 28)
            Text(reason.title)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(minHeight: 48)
          .background(MIRATheme.Color.surface)
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(MIRATheme.Color.hairline, lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.miraPress)
      }
    }
  }

  private var detailsStep: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      if let selectedReason {
        Text(selectedReason.title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
      }

      Text("You can add more information to help us review this report.")
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      TextEditor(text: $details)
        .focused($detailsFocused)
        .font(.system(size: 15))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minHeight: 120, maxHeight: 160)
        .padding(10)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
          if details.isEmpty {
            Text("Add details...")
              .font(.system(size: 15))
              .foregroundStyle(MIRATheme.Color.textMuted)
              .padding(.horizontal, 16)
              .padding(.vertical, 18)
              .allowsHitTesting(false)
          }
        }
        .onChange(of: details) { _, newValue in
          if newValue.count > 500 {
            details = String(newValue.prefix(500))
          }
        }

      Text("\(details.count)/500")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(maxWidth: .infinity, alignment: .trailing)

      if let errorMessage {
        MIRAReportNotice(message: errorMessage, isError: true)
      }
    }
  }

  private var confirmationStep: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
      VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
        Image(systemName: lastResult?.duplicate == true ? "checkmark.seal" : "checkmark.circle.fill")
          .font(.system(size: 36, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)

        Text(lastResult?.duplicate == true ? "Already reported" : "Report submitted")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)

        Text(lastResult?.duplicate == true ? "You already reported this. Thanks, we're reviewing it." : "Thanks for helping keep Captro safe. We'll review this and take action if it breaks our rules.")
          .font(.system(size: 15, weight: .regular))
          .lineSpacing(3)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if lastResult?.blocked == true {
        MIRAReportNotice(message: "You blocked this user. They won't be able to message you.", isError: false)
      }
    }
  }

  @ViewBuilder
  private var footer: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      if step == .details {
        Button {
          Task { await submit(blockUser: false) }
        } label: {
          footerButtonLabel("Submit report", systemImage: "paperplane.fill", filled: true)
        }
        .disabled(isSubmitting || selectedReason == nil)
        .buttonStyle(.miraPress)

        if canBlock {
          Button {
            Task { await submit(blockUser: true) }
          } label: {
            footerButtonLabel("Submit and block user", systemImage: "hand.raised.fill", filled: false)
          }
          .disabled(isSubmitting || selectedReason == nil)
          .buttonStyle(.miraPress)
        }

        HStack(spacing: MIRATheme.Space.sm) {
          Button("Back") {
            detailsFocused = false
            withAnimation(.easeInOut(duration: 0.18)) {
              step = .reasons
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(maxWidth: .infinity, minHeight: 38)

          Button("Cancel", action: onClose)
            .buttonStyle(.plain)
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 38)
        }
        .font(.system(size: 14, weight: .semibold))
      } else if step == .confirmation {
        if canBlock && lastResult?.blocked != true {
          Button {
            Task { await blockTargetAfterReport() }
          } label: {
            footerButtonLabel("Block this user", systemImage: "hand.raised.fill", filled: false)
          }
          .disabled(isSubmitting)
          .buttonStyle(.miraPress)
        }

        Button {
          hideContentAndClose()
        } label: {
          footerButtonLabel("Hide this content", systemImage: "eye.slash", filled: false)
        }
        .buttonStyle(.miraPress)

        Button {
          onClose()
        } label: {
          footerButtonLabel("Done", systemImage: "checkmark", filled: true)
        }
        .buttonStyle(.miraPress)
      }
    }
    .padding(.horizontal, MIRATheme.Space.lg)
    .padding(.top, MIRATheme.Space.sm)
    .padding(.bottom, MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .top) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private func footerButtonLabel(_ title: String, systemImage: String, filled: Bool) -> some View {
    HStack(spacing: MIRATheme.Space.xs) {
      if isSubmitting && (title.contains("Submit") || title.contains("Block")) {
        ProgressView()
          .tint(filled ? .white : MIRATheme.Color.textPrimary)
          .scaleEffect(0.86)
      } else {
        Image(systemName: systemImage)
          .font(.system(size: 14, weight: .bold))
      }
      Text(title)
        .font(.system(size: 15, weight: .semibold))
    }
    .foregroundStyle(filled ? .white : MIRATheme.Color.textPrimary)
    .frame(maxWidth: .infinity, minHeight: 46)
    .background(filled ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft)
    .clipShape(Capsule())
    .opacity(isSubmitting ? 0.72 : 1)
  }

  private var headerTitle: String {
    switch step {
    case .reasons: return "Report"
    case .details: return "Add details"
    case .confirmation: return "Report submitted"
    }
  }

  private var headerSubtitle: String {
    switch step {
    case .reasons: return "Help us understand what happened."
    case .details: return "This is optional and private to Captro moderation."
    case .confirmation: return "Your report was sent to moderation."
    }
  }

  private var iconForTarget: String {
    switch target.targetType {
    case "comment": return "bubble.left.and.bubble.right"
    case "user", "profile": return "person.crop.circle.badge.exclamationmark"
    case "message": return "message.badge"
    case "story": return "circle.dashed.inset.filled"
    case "discover_post": return "square.grid.3x3"
    default: return "photo"
    }
  }

  private var canBlock: Bool {
    target.ownerUserId?.isEmpty == false
  }

  private func submit(blockUser: Bool) async {
    guard let selectedReason, !isSubmitting else { return }
    isSubmitting = true
    errorMessage = nil
    detailsFocused = false
    defer { isSubmitting = false }

    do {
      let response: MIRAReportSubmitResponse = try await api.post(
        "/reports",
        body: MIRAReportSubmitBody(
          targetType: target.targetType,
          targetId: target.targetId,
          reason: selectedReason.id,
          details: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details.trimmingCharacters(in: .whitespacesAndNewlines),
          blockUser: blockUser,
          hideContent: blockUser
        )
      )
      let result = MIRAReportResult(
        reportId: response.id,
        duplicate: response.duplicate == true,
        blocked: response.blocked == true,
        hidden: blockUser && response.hidden == true
      )
      lastResult = result
      onSubmitted(result)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      withAnimation(.easeInOut(duration: 0.20)) {
        step = .confirmation
      }
    } catch {
      errorMessage = "Couldn't submit report. Please try again."
      UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
  }

  private func blockTargetAfterReport() async {
    guard let ownerUserId = target.ownerUserId, !ownerUserId.isEmpty, !isSubmitting else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    do {
      let _: EmptyResponse? = try await api.post("/users/\(ownerUserId)/block", body: EmptyBody())
      let result = MIRAReportResult(reportId: lastResult?.reportId, duplicate: lastResult?.duplicate == true, blocked: true, hidden: lastResult?.hidden == true)
      lastResult = result
      onSubmitted(result)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    } catch {
      errorMessage = "Couldn't block this user. Please try again."
      UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
  }

  private func hideContentAndClose() {
    let result = MIRAReportResult(reportId: lastResult?.reportId, duplicate: lastResult?.duplicate == true, blocked: lastResult?.blocked == true, hidden: true)
    lastResult = result
    onSubmitted(result)
    onClose()
  }
}

private struct MIRAReportNotice: View {
  let message: String
  let isError: Bool

  var body: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
        .font(.system(size: 14, weight: .semibold))
      Text(message)
        .font(.system(size: 13, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(isError ? Color.red : MIRATheme.Color.forest)
    .padding(MIRATheme.Space.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background((isError ? Color.red : MIRATheme.Color.forest).opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
