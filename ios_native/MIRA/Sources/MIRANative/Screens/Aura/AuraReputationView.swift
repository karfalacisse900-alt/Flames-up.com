import SwiftUI

/// Aura Mobile's Reputation tab: the user's own Aura Score and reputation event history.
/// Users never choose a point delta directly (e.g. "+50 Aura") -- the reputation engine derives
/// impact from verified events. This screen only displays what the engine has produced.
public struct AuraReputationView: View {
  let api: MIRAAPIClient

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        MIRAEmptyState(
          title: "No Aura Score is displayed",
          message: "Reputation events come from the Aura network after a verified purchase. There are no invented scores, badges, or history shown here.",
          systemImage: "chart.line.uptrend.xyaxis"
        )
        .miraCardSurface()
        .padding(MIRATheme.Space.lg)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Reputation")
    }
  }
}
