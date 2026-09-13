import GoogleSignIn
import SwiftUI

/// Google's supplied control preserves its logo, typography and localized button treatment.
struct MIRAGoogleSignInControl: UIViewRepresentable {
  let isEnabled: Bool
  let action: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  func makeCoordinator() -> Coordinator { Coordinator(action: action) }

  func makeUIView(context: Context) -> GIDSignInButton {
    let button = GIDSignInButton()
    button.style = .standard
    button.addTarget(context.coordinator, action: #selector(Coordinator.activate), for: .touchUpInside)
    button.accessibilityLabel = "Continue with Google"
    button.isAccessibilityElement = true
    return button
  }

  func updateUIView(_ button: GIDSignInButton, context: Context) {
    context.coordinator.action = action
    button.isEnabled = isEnabled
    button.colorScheme = colorScheme == .dark ? .dark : .light
  }

  final class Coordinator: NSObject {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func activate() { action() }
  }
}
