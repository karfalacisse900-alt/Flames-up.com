import SwiftUI

/// Content-sized native choices. No second panel, manual scrim or confirmation step.
struct CaptroSelectionSheet<Content: View>: View {
  let title: String
  var onBack: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content
  @State private var contentHeight: CGFloat = 360
  @State private var selectedDetent: PresentationDetent = .height(360)
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 0, content: content)
          .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
          .background(GeometryReader { geometry in
            Color.clear.preference(key: CaptroSelectionHeight.self, value: geometry.size.height)
          })
          .onPreferenceChange(CaptroSelectionHeight.self) { height in
            guard height > 0 else { return }
            let resolved = max(180, min(height + 64, 600))
            guard abs(resolved - contentHeight) > 1 else { return }
            contentHeight = resolved
            if selectedDetent != .large { selectedDetent = .height(resolved) }
          }
      }
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if let onBack {
          ToolbarItem(placement: .cancellationAction) { Button("Back", systemImage: "chevron.left", action: onBack) }
        }
      }
      .background(MIRATheme.Color.surface)
    }
    .tint(MIRATheme.Color.forest)
    .presentationBackground(MIRATheme.Color.surface)
    .presentationDragIndicator(.visible)
    .presentationDetents([.height(contentHeight), .large], selection: $selectedDetent)
  }
}
private struct CaptroSelectionHeight: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct CaptroSelectionRow: View {
  let title: String
  var subtitle: String? = nil
  var symbol: String? = nil
  var selected = false
  var disclosure = false
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if let symbol { Image(systemName: symbol).frame(width: 20).accessibilityHidden(true) }
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.body)
          if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary) }
        }.fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        if selected { Image(systemName: "checkmark").foregroundStyle(MIRATheme.Color.forest) }
        else if disclosure { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(MIRATheme.Color.textMuted) }
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
      .padding(.vertical, subtitle == nil ? 0 : 6)
      .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}
