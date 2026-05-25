import SwiftUI
import MIRANative

@main
struct MIRAApp: App {
  @UIApplicationDelegateAdaptor(MIRAAppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  init() {
    MIRAPerformanceTimeline.mark("cold_launch_app_init")
  }

  var body: some Scene {
    WindowGroup {
      MIRANativeRootView()
        .preferredColorScheme(.light)
        .onAppear {
          MIRAPerformanceTimeline.markOnce("time_to_first_window")
        }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .active else { return }
          MIRAPerformanceTimeline.mark("warm_launch_or_resume")
          MIRAMemoryMetrics.log("scene_active")
        }
    }
  }
}
