import SwiftUI

struct CaptroVerifiedBadge: View {
  let verified: Bool
  @ScaledMetric(relativeTo: .caption) private var size = 13.0
  var body: some View {
    if verified {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(CaptroTeaStyle.accent)
        .accessibilityLabel("Verified account")
        .fixedSize()
    }
  }
}
