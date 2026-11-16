import Foundation
import Realtime

private struct MIRAChatRealtimeConfig: Decodable {
  let url: URL
  let publishableKey: String
}

/// Realtime carries invalidation signals only. Message bodies are read from the
/// existing authorized cursor API, which remains the source of truth.
@MainActor
enum MIRAChatRealtime {
  static func observe(
    kind: ConversationNativeKind,
    userId: String,
    api: MIRAAPIClient,
    onChange: @escaping @MainActor @Sendable () async -> Void,
    onConnectionChange: @escaping @MainActor @Sendable (Bool) -> Void
  ) async {
    let owner = api.presentationScope
    // Recover an initial failed join as well as SDK-managed socket reconnects.
    // The authorized cursor API continues polling throughout. Stop retries on
    // disappearance/account change; never start a parallel observer per retry.
    for attempt in 0..<5 {
      guard !Task.isCancelled, owner == api.presentationScope else { return }
      await observeOnce(kind: kind, userId: userId, api: api,
        onChange: { if owner == api.presentationScope, !Task.isCancelled { await onChange() } },
        onConnectionChange: { connected in if owner == api.presentationScope { onConnectionChange(connected) } })
      guard !Task.isCancelled, owner == api.presentationScope else { return }
      MIRAApplePerformanceLogger.event("chat_socket_retry", detail: "attempt=\(attempt + 1)")
      do { try await Task.sleep(for: .seconds(min(60, 2 * (1 << attempt)))) } catch { return }
    }
  }
  private static func observeOnce(
    kind: ConversationNativeKind,
    userId: String,
    api: MIRAAPIClient,
    onChange: @escaping @MainActor @Sendable () async -> Void,
    onConnectionChange: @escaping @MainActor @Sendable (Bool) -> Void
  ) async {
    onConnectionChange(false)
    guard !userId.isEmpty else { return }
    guard let config: MIRAChatRealtimeConfig = try? await api.get("/chat/realtime-config"),
          config.url.scheme == "https",
          !config.publishableKey.isEmpty else { return }

    let tokenProvider = MIRAKeychainSessionProvider()
    guard let initialToken = await tokenProvider.accessToken(), !initialToken.isEmpty else { return }
    let client = RealtimeClientV2(
      url: config.url.appendingPathComponent("realtime/v1"),
      options: RealtimeClientOptions(
        headers: ["apiKey": config.publishableKey],
        disconnectOnEmptyChannelsAfter: 0,
        accessToken: { await tokenProvider.accessToken() }
      )
    )
    await client.setAuth(initialToken)

    let channel: RealtimeChannelV2
    let subscriptions: [RealtimeSubscription]
    switch kind {
    case .direct:
      // Realtime supports one equality filter per listener. RLS still ensures
      // the signed-in user sees only their own direct messages.
      channel = client.channel("captro-direct-\(userId)")
      let sent = channel.onPostgresChange(
        InsertAction.self, schema: "public", table: "app_messages",
        filter: .eq("sender_id", value: userId), select: ["id", "sender_id", "receiver_id"]
      ) { _ in Task { await onChange() } }
      let received = channel.onPostgresChange(
        InsertAction.self, schema: "public", table: "app_messages",
        filter: .eq("receiver_id", value: userId), select: ["id", "sender_id", "receiver_id"]
      ) { _ in Task { await onChange() } }
      subscriptions = [sent, received]
    case let .group(groupId):
      channel = client.channel("captro-group-\(groupId)")
      let group = channel.onPostgresChange(
        InsertAction.self, schema: "public", table: "app_group_messages",
        filter: .eq("group_id", value: groupId), select: ["id", "group_id"]
      ) { _ in Task { await onChange() } }
      subscriptions = [group]
    }

    do {
      try await channel.subscribeWithError()
      onConnectionChange(true)
      await onChange() // Recover changes between the initial fetch and join.
      var wasSubscribed = true
      while !Task.isCancelled {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let subscribed = channel.status == .subscribed
        if subscribed != wasSubscribed {
          onConnectionChange(subscribed)
          if subscribed { await onChange() } // Reconcile missed events on reconnect.
          wasSubscribed = subscribed
        }
      }
    } catch {
      // The caller keeps a bounded visible-only polling fallback.
    }
    onConnectionChange(false)
    subscriptions.forEach { $0.cancel() }
    await client.removeChannel(channel)
    client.disconnect()
  }
}
