import SwiftUI

struct CaptroTeaInterestControl: View {
  @ObservedObject var model: CaptroTeaNoteSignal
  let signedIn: Bool
  let signIn: () -> Void
  var body: some View {
    HStack(spacing: 0) {
      choice("interested", symbol: "plus", label: "I’m interested")
      choice("pass", symbol: "minus", label: "Pass")
    }
    .background {
      Capsule().strokeBorder(MIRATheme.Color.textSecondary.opacity(0.7), lineWidth: 0.6).frame(width: 64, height: 24)
    }
    .overlay { Rectangle().fill(MIRATheme.Color.textSecondary.opacity(0.6)).frame(width: 0.5, height: 14).allowsHitTesting(false) }
    .fixedSize()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("tea.interest." + model.id)
  }
  private func choice(_ value: String, symbol: String, label: String) -> some View {
    Button {
      if signedIn { Task { await model.choose(value) } } else { signIn() }
    } label: {
      Image(systemName: symbol).font(.system(size: 14, weight: model.interest == value ? .bold : .regular))
        .foregroundStyle(model.interest == value ? CaptroTeaStyle.accent : MIRATheme.Color.textPrimary)
        .offset(x: value == "interested" ? 6 : -6)
        .frame(width: 44, height: 44)
        .background { if model.interest == value { Capsule().fill(CaptroTeaStyle.tint).frame(width: 28, height: 20).offset(x: value == "interested" ? 6 : -6) } }
        .contentShape(Rectangle())
    }.buttonStyle(.plain).disabled(model.busy || !model.valid)
      .accessibilityLabel(label)
      .accessibilityValue(model.busy ? "Saving" : model.interest == value ? "Selected" : "Not selected")
      .accessibilityHint(model.error != nil ? "Retry saving your choice" : model.interest == value ? "Tap again to undo" : "Private. Does not follow the author or change the Note’s rank.")
      .accessibilityAddTraits(model.interest == value ? .isSelected : [])
      .accessibilityIdentifier("tea.interest." + value + "." + model.id)
  }
}

struct CaptroTeaInsightsView: View {
  @ObservedObject var model: CaptroTeaNoteSignal
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Your Note Insights").miraText(.label)
      Text("Only you can see these totals.").miraText(.metadata).foregroundStyle(MIRATheme.Color.textSecondary)
      if let insights = model.insights {
        TeaLinkFlow(spacing: 12) {
          Text("\(insights.uniqueOpens) unique opens")
          Text("\(insights.interested) interested")
          Text("\(insights.replies) replies")
        }.miraText(.metadata)
      } else if model.insightsError == nil { ProgressView("Loading Insights").font(.caption) }
      if let error = model.insightsError {
        Text(error).miraText(.metadata)
        Button("Retry Insights") { Task { await model.loadInsights(force: true) } }.frame(minHeight: 44)
      }
    }.padding(.vertical, 8).accessibilityIdentifier("tea.insights")
  }
}
