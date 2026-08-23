import SwiftUI

/// Aura Mobile's Home tab: reputation summary, wallet balance, recent verified activity, and
/// recently interacted-with businesses. Every value here must come from a real Aura Mobile
/// Gateway response once one exists — until then this renders an honest "not connected" state
/// rather than inventing a score, balance, or activity feed.
public struct AuraHomeView: View {
  let api: MIRAAPIClient

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.lg) {
          reputationCard
          MIRAEmptyState(
            title: "Not connected to Aura",
            message: "Home will show your Aura Reputation, wallet balance, and recent verified activity once this device is connected to an Aura Mobile Gateway.",
            systemImage: "antenna.radiowaves.left.and.right.slash"
          )
          .miraCardSurface()
        }
        .padding(MIRATheme.Space.lg)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Aura")
    }
  }

  private var reputationCard: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      Text("Aura Reputation")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
      Text("Unavailable")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text("No Aura Score is displayed until this device has a verified, connected identity.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MIRATheme.Space.lg)
    .miraCardSurface()
  }
}
