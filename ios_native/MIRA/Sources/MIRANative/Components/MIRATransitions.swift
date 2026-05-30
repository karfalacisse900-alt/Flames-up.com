import SwiftUI
import UIKit

public enum MIRATransitionTiming {
  public static let buttonPress: Double = 0.12
  public static let popupOpen: Double = 0.22
  public static let popupClose: Double = 0.18
  public static let sheetOpen: Double = 0.32
  public static let sheetClose: Double = 0.26
  public static let fullScreenOpen: Double = 0.30
  public static let fullScreenClose: Double = 0.24
}

private enum MIRAPresentationGeometry {
  static func sheetHeight(for proxy: GeometryProxy, preferredFraction: CGFloat, maxHeight: CGFloat) -> CGFloat {
    let available = max(320, proxy.size.height - 10)
    let preferred = proxy.size.height * preferredFraction
    return min(max(340, preferred), min(maxHeight, available))
  }
}

public extension View {
  func miraBottomSheet<Sheet: View>(
    isPresented: Binding<Bool>,
    preferredHeightFraction: CGFloat = 0.76,
    maxHeight: CGFloat = 720,
    scrimOpacity: Double = 0.22,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder sheet: @escaping (_ dismiss: @escaping () -> Void) -> Sheet
  ) -> some View {
    modifier(
      MIRABottomSheetModifier(
        isPresented: isPresented,
        preferredHeightFraction: preferredHeightFraction,
        maxHeight: maxHeight,
        scrimOpacity: scrimOpacity,
        onDismissed: onDismissed,
        sheet: sheet
      )
    )
  }

  func miraFadeScaleOverlay<Overlay: View>(
    isPresented: Binding<Bool>,
    scrimOpacity: Double = 0.18,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping (_ dismiss: @escaping () -> Void) -> Overlay
  ) -> some View {
    modifier(
      MIRAFadeScaleOverlayModifier(
        isPresented: isPresented,
        scrimOpacity: scrimOpacity,
        onDismissed: onDismissed,
        overlay: overlay
      )
    )
  }

  func miraFullScreenOverlay<Overlay: View>(
    isPresented: Binding<Bool>,
    background: Color = .black,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping (_ dismiss: @escaping () -> Void) -> Overlay
  ) -> some View {
    modifier(
      MIRAFullScreenBoolOverlayModifier(
        isPresented: isPresented,
        background: background,
        onDismissed: onDismissed,
        overlay: overlay
      )
    )
  }

  func miraFullScreenOverlay<Item: Identifiable, Overlay: View>(
    item: Binding<Item?>,
    background: Color = .black,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping (_ item: Item, _ dismiss: @escaping () -> Void) -> Overlay
  ) -> some View {
    modifier(
      MIRAFullScreenItemOverlayModifier(
        item: item,
        background: background,
        onDismissed: onDismissed,
        overlay: overlay
      )
    )
  }

  func miraHideTabBarOnAppear() -> some View {
    modifier(MIRAHideTabBarModifier())
  }
}

private struct MIRAHideTabBarModifier: ViewModifier {
  @State private var token = UUID()

  func body(content: Content) -> some View {
    content
      .toolbar(.hidden, for: .tabBar)
      .onAppear {
        Task { @MainActor in
          MIRATabBarVisibilityStore.hide(token)
        }
      }
      .onDisappear {
        Task { @MainActor in
          MIRATabBarVisibilityStore.show(token)
        }
      }
  }
}

@MainActor
private enum MIRATabBarVisibilityStore {
  private static var hiddenTokens = Set<UUID>()

  static func hide(_ token: UUID) {
    hiddenTokens.insert(token)
    setTabBarHidden(true)
  }

  static func show(_ token: UUID) {
    hiddenTokens.remove(token)
    setTabBarHidden(!hiddenTokens.isEmpty)
  }

  private static func setTabBarHidden(_ hidden: Bool) {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .compactMap(\.rootViewController)
      .compactMap { $0.miraTabBarController }
      .forEach { tabBarController in
        guard tabBarController.tabBar.isHidden != hidden else { return }
        tabBarController.tabBar.isHidden = hidden
      }
  }
}

private extension UIViewController {
  var miraTabBarController: UITabBarController? {
    if let tabBarController = self as? UITabBarController {
      return tabBarController
    }
    if let owningTabBar = self.tabBarController {
      return owningTabBar
    }
    if let navigationController = self as? UINavigationController {
      return navigationController.visibleViewController?.miraTabBarController
        ?? navigationController.topViewController?.miraTabBarController
    }
    if let presentedViewController {
      return presentedViewController.miraTabBarController
    }
    for child in children {
      if let found = child.miraTabBarController {
        return found
      }
    }
    return nil
  }
}

private struct MIRABottomSheetModifier<Sheet: View>: ViewModifier {
  @Binding var isPresented: Bool
  let preferredHeightFraction: CGFloat
  let maxHeight: CGFloat
  let scrimOpacity: Double
  let onDismissed: (() -> Void)?
  let sheet: (_ dismiss: @escaping () -> Void) -> Sheet
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isMounted = false
  @State private var isVisible = false
  @GestureState private var dragOffset: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .overlay {
        if isMounted {
          GeometryReader { proxy in
            let height = MIRAPresentationGeometry.sheetHeight(
              for: proxy,
              preferredFraction: preferredHeightFraction,
              maxHeight: maxHeight
            )
            ZStack(alignment: .bottom) {
              Color.black
                .opacity(isVisible ? scrimOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

              sheet(dismiss)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(MIRATheme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.sheet, style: .continuous))
                .shadow(color: .black.opacity(isVisible ? 0.16 : 0), radius: 24, x: 0, y: -8)
                .padding(.horizontal, proxy.size.width > 700 ? 76 : 0)
                .offset(y: sheetOffset(height: height, safeAreaBottom: proxy.safeAreaInsets.bottom))
                .simultaneousGesture(sheetDragGesture(threshold: min(180, height * 0.24)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
          }
          .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
          .zIndex(900)
          .allowsHitTesting(isMounted)
        }
      }
      .onAppear {
        if isPresented {
          present()
        }
      }
      .onChange(of: isPresented) { _, newValue in
        newValue ? present() : dismissFromExternalState()
      }
      .animation(sheetAnimation, value: isVisible)
      .animation(sheetAnimation, value: dragOffset)
  }

  private var sheetAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.02)
  }

  private var dismissDelay: Double {
    reduceMotion ? 0.08 : MIRATransitionTiming.sheetClose
  }

  private func sheetOffset(height: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
    guard isVisible else { return height + safeAreaBottom + 56 }
    return max(0, dragOffset)
  }

  private func sheetDragGesture(threshold: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 18, coordinateSpace: .global)
      .updating($dragOffset) { value, state, _ in
        guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
        state = value.translation.height
      }
      .onEnded { value in
        let downward = value.translation.height > threshold || value.predictedEndTranslation.height > threshold * 1.35
        if downward {
          dismiss()
        }
      }
  }

  private func present() {
    isMounted = true
    DispatchQueue.main.async {
      withAnimation(sheetAnimation) {
        isVisible = true
      }
    }
  }

  private func dismiss() {
    guard isMounted, isVisible else { return }
    withAnimation(sheetAnimation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      isPresented = false
      isMounted = false
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard isMounted else { return }
    withAnimation(sheetAnimation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard !isPresented else { return }
      isMounted = false
      onDismissed?()
    }
  }
}

private struct MIRAFadeScaleOverlayModifier<Overlay: View>: ViewModifier {
  @Binding var isPresented: Bool
  let scrimOpacity: Double
  let onDismissed: (() -> Void)?
  let overlay: (_ dismiss: @escaping () -> Void) -> Overlay
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isMounted = false
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .overlay {
        if isMounted {
          ZStack {
            Color.black
              .opacity(isVisible ? scrimOpacity : 0)
              .ignoresSafeArea()
              .contentShape(Rectangle())
              .onTapGesture(perform: dismiss)

            overlay(dismiss)
              .opacity(isVisible ? 1 : 0)
              .scaleEffect(reduceMotion || isVisible ? 1 : 0.975)
          }
          .zIndex(850)
          .allowsHitTesting(isMounted)
        }
      }
      .onAppear {
        if isPresented {
          present()
        }
      }
      .onChange(of: isPresented) { _, newValue in
        newValue ? present() : dismissFromExternalState()
      }
      .animation(animation, value: isVisible)
  }

  private var animation: Animation {
    reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: MIRATransitionTiming.popupOpen)
  }

  private var dismissDelay: Double {
    reduceMotion ? 0.08 : MIRATransitionTiming.popupClose
  }

  private func present() {
    isMounted = true
    DispatchQueue.main.async {
      withAnimation(animation) {
        isVisible = true
      }
    }
  }

  private func dismiss() {
    guard isMounted, isVisible else { return }
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      isPresented = false
      isMounted = false
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard isMounted else { return }
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard !isPresented else { return }
      isMounted = false
      onDismissed?()
    }
  }
}

private struct MIRAFullScreenBoolOverlayModifier<Overlay: View>: ViewModifier {
  @Binding var isPresented: Bool
  let background: Color
  let onDismissed: (() -> Void)?
  let overlay: (_ dismiss: @escaping () -> Void) -> Overlay
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isMounted = false
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .overlay {
        if isMounted {
          ZStack {
            background
              .opacity(isVisible ? 1 : 0)
              .ignoresSafeArea()
            overlay(dismiss)
              .opacity(isVisible ? 1 : 0)
              .scaleEffect(reduceMotion || isVisible ? 1 : 0.985)
          }
          .ignoresSafeArea()
          .zIndex(950)
          .allowsHitTesting(isMounted)
        }
      }
      .onAppear {
        if isPresented {
          present()
        }
      }
      .onChange(of: isPresented) { _, newValue in
        newValue ? present() : dismissFromExternalState()
      }
      .animation(animation, value: isVisible)
  }

  private var animation: Animation {
    reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: MIRATransitionTiming.fullScreenOpen)
  }

  private var dismissDelay: Double {
    reduceMotion ? 0.08 : MIRATransitionTiming.fullScreenClose
  }

  private func present() {
    isMounted = true
    DispatchQueue.main.async {
      withAnimation(animation) {
        isVisible = true
      }
    }
  }

  private func dismiss() {
    guard isMounted, isVisible else { return }
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      isPresented = false
      isMounted = false
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard isMounted else { return }
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard !isPresented else { return }
      isMounted = false
      onDismissed?()
    }
  }
}

private struct MIRAFullScreenItemOverlayModifier<Item: Identifiable, Overlay: View>: ViewModifier {
  @Binding var item: Item?
  let background: Color
  let onDismissed: (() -> Void)?
  let overlay: (_ item: Item, _ dismiss: @escaping () -> Void) -> Overlay
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mountedItem: Item?
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .overlay {
        if let presentedItem = mountedItem {
          ZStack {
            background
              .opacity(isVisible ? 1 : 0)
              .ignoresSafeArea()
            overlay(presentedItem, dismiss)
              .opacity(isVisible ? 1 : 0)
              .scaleEffect(reduceMotion || isVisible ? 1 : 0.985)
          }
          .ignoresSafeArea()
          .zIndex(950)
          .allowsHitTesting(true)
        }
      }
      .onAppear(perform: syncWithBinding)
      .onChange(of: item?.id) { _, _ in
        syncWithBinding()
      }
      .animation(animation, value: isVisible)
  }

  private var animation: Animation {
    reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: MIRATransitionTiming.fullScreenOpen)
  }

  private var dismissDelay: Double {
    reduceMotion ? 0.08 : MIRATransitionTiming.fullScreenClose
  }

  private func syncWithBinding() {
    if let item {
      mountedItem = item
      DispatchQueue.main.async {
        withAnimation(animation) {
          isVisible = true
        }
      }
    } else {
      dismissFromExternalState()
    }
  }

  private func dismiss() {
    guard mountedItem != nil, isVisible else { return }
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      item = nil
      mountedItem = nil
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard mountedItem != nil else { return }
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard item == nil else { return }
      mountedItem = nil
      onDismissed?()
    }
  }
}
