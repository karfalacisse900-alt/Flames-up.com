import SwiftUI

/// The compact, anchored choice surface shared by Create and Home.
/// The texture is deterministic and drawn only with the menu, never animated.
struct CaptroEditorialMenu<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased())
        .font(.system(.caption2, design: .serif, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(MIRATheme.Color.editorialMenuText.opacity(0.82))
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
      content()
    }
    .padding(10)
    .frame(width: dynamicTypeSize.isAccessibilitySize ? 310 : 266)
    .background {
      MIRATheme.Color.editorialOlive
        .overlay(CaptroPaperGrain().allowsHitTesting(false))
    }
    .overlay(Rectangle().stroke(MIRATheme.Color.editorialMenuBorder, lineWidth: 0.75))
    .presentationBackground(MIRATheme.Color.editorialOlive)
    .presentationCompactAdaptation(.popover)
  }
}

struct CaptroEditorialMenuRow: View {
  let title: String
  var selected = false
  var disclosure = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Text(title)
          .font(.system(.body, design: .serif, weight: selected ? .semibold : .regular))
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 6)
        if selected {
          Image(systemName: "checkmark")
            .font(.caption.weight(.semibold))
            .accessibilityHidden(true)
        } else if disclosure {
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .accessibilityHidden(true)
        }
      }
      .foregroundStyle(MIRATheme.Color.editorialInk)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .background(MIRATheme.Color.editorialCream)
      .overlay(Rectangle().stroke(MIRATheme.Color.editorialBorder, lineWidth: 0.65))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct CaptroPaperGrain: View {
  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      guard size.width > 0, size.height > 0 else { return }
      for column in stride(from: 4.0, through: size.width, by: 13.0) {
        for row in stride(from: 5.0, through: size.height, by: 17.0) {
          let offset = CGFloat((Int(column * 7 + row * 11) % 7) - 3)
          let dot = CGRect(x: column + offset, y: row, width: 0.7, height: 0.7)
          context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.045)))
        }
      }
    }
    .accessibilityHidden(true)
  }
}
