import SwiftUI
import MIRANative

@main
struct MIRAApp: App {
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      MIRANativeRootView()
        .preferredColorScheme(.light)
    }
  }
}
