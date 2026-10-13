#if DEBUG
import SwiftUI

/// Simulator-only UI entry points. These never substitute for production data or payments.
public struct CaptroDesignQualityTestView: View {
  @StateObject private var session = MIRAAuthSession()
  @State private var showSheet = false
  @State private var showActions = false
  @State private var text = ""
  @State private var cameraDarkChrome = false
  private let api = MIRAAPIClient()

  public init() {}

  public var body: some View {
    Group {
      if ProcessInfo.processInfo.arguments.contains("--captro-favorites-review") {
        CaptroFavoritesReviewHost()
      } else if ProcessInfo.processInfo.arguments.contains("--captro-presentation-review") {
        CaptroPresentationReviewHost()
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-cover-runtime") {
        CaptroCoverRuntimeTestHost()
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-auth") {
        AuthNativeView(session: session, api: api)
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-settings") {
        SettingsNavigationTestHost(api: api)
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-appearance") {
        NavigationStack { PreferenceSettingsNativeView() }
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-search") {
        NavigationStack { SearchUsersNativeView(api: api) }
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-composer") {
        CreatePostNativeView(api: CaptroComposerTestAPI.make(), initialCaption:
          ProcessInfo.processInfo.arguments.contains("--captro-composer-legacy-draft") ? "Keep my saved caption." : nil)
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-profile") {
        ProfileNativeView(api: CaptroComposerTestAPI.make())
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-chat") {
        NavigationStack { ChatNativeView(api: CaptroComposerTestAPI.make(), currentUserId: "composer-ui-test") }
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-story") {
        CaptroStoryPresentationTestHost()
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-capture") {
        CaptroCameraTabReviewHost(media: cameraReviewFixture)
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-legal") {
        NavigationStack { PrivacyPolicyView() }
      } else {
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              Text("Everyday controls").font(.title2.weight(.semibold))
              MIRAFormInput(title: "Name", text: $text)
              MIRAPrimaryButton("Open sheet") { showSheet = true }
              MIRAPrimaryButton("Unavailable action") {}.disabled(true)
              MIRAPrimaryButton("More actions") { showActions = true }
              MIRAEmptyState(title: "Nothing saved yet", message: "Your saved posts will appear here.", systemImage: "bookmark")
            }
            .padding(24)
          }
          .navigationTitle("Captro UI quality")
          .navigationBarTitleDisplayMode(.inline)
          .background(MIRATheme.Color.appBackground)
        }
        .miraBottomSheet(isPresented: $showSheet) { dismiss in
          VStack(spacing: 0) {
            HStack {
              Text("Saved posts").font(.headline)
              Spacer()
              Button("Done", action: dismiss).frame(minHeight: 44)
            }.padding(.horizontal, 20).padding(.top, 24)
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(0..<30) { index in
                  Text("Saved post \(index)").font(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
              }.padding(20)
            }.accessibilityIdentifier("quality.sheet.scroll")
          }
        }
        .miraActionModal(isPresented: $showActions) { dismiss in
          MIRAActionModalCard {
            MIRAActionModalButton(title: "Save for later", systemImage: "bookmark", action: dismiss)
            MIRAActionModalButton(title: "Cancel", systemImage: "xmark", action: dismiss)
          }
        }
      }
    }
    .environmentObject(MIRALocalization.shared)
    .preferredColorScheme(cameraDarkChrome || ProcessInfo.processInfo.arguments.contains("--captro-quality-dark") ? .dark : .light)
    .onPreferenceChange(CaptroCameraDarkChromePreferenceKey.self) { cameraDarkChrome = $0 }
    .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--captro-quality-large-text") ? .accessibility2 : .large)
  }

  private var cameraReviewFixture: MIRAPickedMedia? {
    guard ProcessInfo.processInfo.arguments.contains("--captro-camera-review-fixture") else { return nil }
    // Clearly identified diagnostic chart, not a simulated camera capture or quality claim.
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200), format: format).image { context in
      UIColor(red: 0.82, green: 0.77, blue: 0.66, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
      UIColor.darkGray.setStroke(); context.cgContext.setLineWidth(8)
      context.cgContext.stroke(CGRect(x: 8, y: 8, width: 884, height: 1184))
      ("REVIEW TEST CHART\n900 × 1200\nNot a camera capture" as NSString).draw(in: CGRect(x: 70, y: 470, width: 760, height: 260),
        withAttributes: [.font: UIFont.systemFont(ofSize: 42), .foregroundColor: UIColor.black])
    }
    return MIRAPickedMedia(data: image.jpegData(compressionQuality: 0.95)!, kind: .image, fileName: "review-test-chart.jpg", mimeType: "image/jpeg")
  }
}

/// Exercises the production camera inside the same native tab container/safe
/// areas as the app, without authenticating or publishing production content.
private struct CaptroCameraTabReviewHost: View {
  let media: MIRAPickedMedia?
  @State private var selection = 1
  var body: some View {
    TabView(selection: $selection) {
      Text("Home test destination").tag(0).tabItem { Label("Home", systemImage: "house.fill") }
      CaptroCameraNativeView(api: CaptroComposerTestAPI.make(), isActive: selection == 1, initialReviewMedia: media)
        .tag(1).tabItem { Label("Capture", systemImage: "viewfinder") }
      Text("Profile test destination").tag(2).tabItem { Label("Me", systemImage: "person.fill") }
    }
    .tint(MIRATheme.Color.textPrimary)
    .toolbarBackground(MIRATheme.Color.surface, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
  }
}

private struct CaptroStoryPresentationTestHost: View {
  @State private var open = false
  private let api = CaptroComposerTestAPI.make()
  private let group = try! JSONDecoder().decode(MIRAStoryGroup.self, from: Data(#"{"userId":"composer-ui-test","userFullName":"Test Creator","statuses":[{"id":"story-ui-test","userId":"composer-ui-test"}]}"#.utf8))
  var body: some View {
    Button("Open test Story") { open = true }
      .fullScreenCover(isPresented: $open) {
        StoryViewerNativeView(group: group, allGroups: [group], api: api,
          onClose: { open = false }, onReportStory: { _ in }, onOpenLinkedPost: { _ in })
      }
  }
}

/// Exercises pushes inside a real tab hierarchy, rather than a standalone mockup.
private struct SettingsNavigationTestHost: View {
  let api: MIRAAPIClient
  @State private var openSettings = false
  var body: some View {
    TabView {
      NavigationStack {
        Button("Open Settings") { openSettings = true }
          .navigationTitle("Me")
          .navigationDestination(isPresented: $openSettings) { SettingsNativeView(api: api) }
          .task { openSettings = true }
      }.tabItem { Label("Me", systemImage: "person") }
      Text("Home").tabItem { Label("Home", systemImage: "house") }
    }
  }
}
#endif
