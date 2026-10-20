import SwiftUI

/// Full sensor/output proportions, not an aspect-fit into leftover control space.
/// The canvas includes safe areas; chrome independently reserves them.
struct CaptroStudioLayout {
  static let headerHeight: CGFloat = 44
  let preview: CGRect
  let header: CGRect
  let controls: CGRect
  let zoomBottom: CGFloat
  let controlsOverlayFrame: Bool

  init(size: CGSize, top: CGFloat, bottom: CGFloat, aspect: CGFloat, controlsHeight: CGFloat) {
    let width = max(1, size.width)
    let ratio = aspect.isFinite && aspect > 0 ? aspect : 3 / 4
    let height = width / ratio
    header = CGRect(x: 0, y: top, width: width, height: Self.headerHeight)
    controls = CGRect(x: 0, y: max(top + Self.headerHeight, size.height - bottom - controlsHeight), width: width, height: controlsHeight)
    // Photo normally sits below the header. Tall video remains a complete
    // full-width frame inside the screen, behind chrome where necessary.
    let y = min(header.maxY, max(0, (size.height - height) / 2))
    preview = CGRect(x: 0, y: y, width: width, height: height)
    controlsOverlayFrame = preview.minY < header.maxY || preview.maxY > controls.minY
    zoomBottom = max(preview.minY + 44, min(preview.maxY, controls.minY)) - 8
  }
}

/// Capture-only compact navigation. The existing TabView remains the owner of
/// selection and cached destinations; these are ordinary native 44pt buttons.
struct CaptroStudioNavigation: View {
  let home: () -> Void
  let capture: () -> Void
  let profile: () -> Void
  var body: some View {
    HStack(spacing: 0) {
      item("Home", symbol: "house.fill", selected: false, action: home)
      item("Capture", symbol: "viewfinder", selected: true, action: capture)
      item("Me", symbol: "person.fill", selected: false, action: profile)
    }
    .frame(maxWidth: 320).padding(.vertical, 4)
    .frame(maxWidth: .infinity).background(Color.black)
    .accessibilityElement(children: .contain).accessibilityIdentifier("capture.navigation")
  }
  private func item(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: symbol).font(.system(size: 20, weight: .regular))
        Text(title).font(.caption2)
      }.frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? Color.white : .white.opacity(0.7))
        .background(selected ? Color.white.opacity(0.10) : .clear, in: Capsule())
    }.buttonStyle(.plain).accessibilityLabel(title)
      .accessibilityAddTraits(selected ? .isSelected : [])
      .accessibilityIdentifier("capture.navigation." + title.lowercased())
  }
}

struct CaptroStudioTabChrome: ViewModifier {
  let active: Bool
  let home: () -> Void
  let capture: () -> Void
  let profile: () -> Void
  func body(content: Content) -> some View {
    content.toolbar(active ? .hidden : .visible, for: .tabBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if active { CaptroStudioNavigation(home: home, capture: capture, profile: profile) }
      }
  }
}
