import SwiftUI
import UIKit

/// A persistent label and an explicit focus ring keep forms understandable while typing.
struct MIRAFormInput: View {
  let title: String
  @Binding var text: String
  var secure = false
  var keyboardType: UIKeyboardType = .default
  var contentType: UITextContentType? = nil
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .accessibilityHidden(true)
      Group {
        if secure {
          SecureField(title, text: $text)
        } else {
          TextField(title, text: $text)
            .keyboardType(keyboardType)
        }
      }
      .textContentType(contentType)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .focused($isFocused)
      .font(.body)
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(minHeight: 48)
      .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: MIRATheme.Radius.small))
      .overlay {
        RoundedRectangle(cornerRadius: MIRATheme.Radius.small)
          .strokeBorder(isFocused ? MIRATheme.Color.forest : MIRATheme.Color.hairline, lineWidth: isFocused ? 2 : 1)
          .allowsHitTesting(false)
      }
      .accessibilityLabel(title)
    }
  }
}
