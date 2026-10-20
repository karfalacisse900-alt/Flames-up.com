import SwiftUI

/// Supplied outlined wordmark; never recreated with a font or functional icon.
struct CaptroBrandLogo: View {
  var onDark = false
  var body: some View {
    Image(onDark ? "CaptroBrandWhite" : "CaptroLaunchLogo", bundle: .main)
      .resizable().scaledToFit().accessibilityLabel("Captro")
  }
}
