#if DEBUG
import SwiftUI

/// Simulator-only UI entry points. These never substitute for production data or payments.
public struct CaptroDesignQualityTestView: View {
  @StateObject private var session = MIRAAuthSession()
  @State private var showSheet = false
  @State private var showActions = false
  @State private var text = ""
  private let api = MIRAAPIClient()

  public init() {}

  public var body: some View {
    Group {
      if ProcessInfo.processInfo.arguments.contains("--captro-quality-auth") {
        AuthNativeView(session: session, api: api)
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-settings") {
        NavigationStack { SettingsNativeView(api: api) }
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-appearance") {
        NavigationStack { PreferenceSettingsNativeView() }
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-search") {
        NavigationStack { SearchUsersNativeView(api: api) }
      } else if ProcessInfo.processInfo.arguments.contains("--captro-quality-composer") {
        NavigationStack { CreatePostNativeView(api: api) }
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
    .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--captro-quality-dark") ? .dark : .light)
    .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--captro-quality-large-text") ? .accessibility2 : .large)
  }
}
#endif
