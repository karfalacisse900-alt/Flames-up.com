import SwiftUI
import UIKit

struct CaptroFavoriteButton: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  @ObservedObject private var store: CaptroFavoritesStore
  @State private var organizing = false
  init(post: MIRAPost, api: MIRAAPIClient) {
    self.post = post; self.api = api; _store = ObservedObject(wrappedValue: api.favorites)
  }
  var body: some View {
    FavoritePressControl(saved: store.isSaved(post), enabled: !store.busy.contains(post.id), id: post.id,
      tap: { Task { await store.toggle(post) } },
      organize: { if store.requireAccount() { organizing = true; CaptroHaptics.light() } })
      .frame(width: 44, height: 44)
      .sheet(isPresented: $organizing) {
        CaptroFavoritePicker(postID: post.id, api: api)
          .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
      }
  }
}

/// Details reads the same optimistic/confirmed state as Home, without observing
/// the Favorites store in the entire media screen or trusting a stale post copy.
struct CaptroFavoriteMenuAction: View {
  let post: MIRAPost
  @ObservedObject var store: CaptroFavoritesStore
  var body: some View {
    Button { Task { await store.toggle(post) } } label: {
      Label(store.isSaved(post) ? "Remove from Favorites" : "Save to Favorites",
        systemImage: store.isSaved(post) ? "star.fill" : "star")
    }
    .disabled(store.busy.contains(post.id))
  }
}

/// Independent sibling of the media pager. The tap waits for long-press failure,
/// and scroll-view pans cancel both recognizers instead of invoking either action.
private struct FavoritePressControl: UIViewRepresentable {
  let saved: Bool
  let enabled: Bool
  let id: String
  let tap: () -> Void
  let organize: () -> Void
  func makeUIView(context: Context) -> FavoriteControl { FavoriteControl() }
  func updateUIView(_ view: FavoriteControl, context: Context) {
    view.tapAction = tap; view.organizeAction = organize
    // Keep consuming taps while a write is pending. Disabling hit testing lets
    // a rapid second tap fall through to the photo/video underneath this button.
    view.enabled = enabled
    view.accessibilityIdentifier = "favorite.star.\(id)"
    view.accessibilityLabel = saved ? "Remove from Favorites" : "Save to Favorites"
    view.accessibilityHint = "Touch and hold to organize in collections."
    view.accessibilityValue = saved ? "Saved" : "Not saved"
    view.accessibilityTraits = saved ? [.button, .selected] : [.button]
    if !enabled { view.accessibilityTraits.insert(.notEnabled) }
    view.icon.image = UIImage(systemName: saved ? "star.fill" : "star",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
  }
}
private final class FavoriteControl: UIView {
  let icon = UIImageView()
  var enabled = true
  var tapAction: (() -> Void)?
  var organizeAction: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    isAccessibilityElement = true
    let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    material.isUserInteractionEnabled = false
    material.layer.cornerRadius = 11; material.clipsToBounds = true
    material.translatesAutoresizingMaskIntoConstraints = false
    addSubview(material)
    icon.tintColor = .label; icon.contentMode = .center; icon.translatesAutoresizingMaskIntoConstraints = false
    icon.isUserInteractionEnabled = false; addSubview(icon)
    NSLayoutConstraint.activate([
      material.widthAnchor.constraint(equalToConstant: 40), material.heightAnchor.constraint(equalToConstant: 40),
      material.centerXAnchor.constraint(equalTo: centerXAnchor), material.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.leadingAnchor.constraint(equalTo: leadingAnchor), icon.trailingAnchor.constraint(equalTo: trailingAnchor),
      icon.topAnchor.constraint(equalTo: topAnchor), icon.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
    hold.minimumPressDuration = 0.45; hold.allowableMovement = 8
    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
    tap.require(toFail: hold)
    addGestureRecognizer(hold); addGestureRecognizer(tap)
    accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Organize in collection", target: self, selector: #selector(organizeAccessible))]
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func tapped() { guard enabled else { return }; tapAction?() }
  @objc private func held(_ gesture: UILongPressGestureRecognizer) { if enabled && gesture.state == .began { organizeAction?() } }
  @objc private func organizeAccessible() -> Bool { guard enabled else { return false }; organizeAction?(); return true }
  override func accessibilityActivate() -> Bool { guard enabled else { return false }; tapAction?(); return true }
}

struct CaptroFavoriteNotice: View {
  @ObservedObject var store: CaptroFavoritesStore
  var body: some View {
    if let message = store.notice {
      HStack(spacing: 12) {
        Text(message).font(.footnote).fixedSize(horizontal: false, vertical: true)
        if let title = store.noticeAction {
          Button(title) { Task { await store.runNoticeAction() } }.font(.footnote.bold()).frame(minHeight: 44)
        }
        Button { store.dismissNotice() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
          .accessibilityLabel("Dismiss confirmation")
      }
      .padding(.leading, 14).foregroundStyle(MIRATheme.Color.textPrimary)
      .background(MIRATheme.Color.editorialCream)
      .overlay(Rectangle().stroke(MIRATheme.Color.hairline))
      .padding(.horizontal, 16)
      .accessibilityElement(children: .contain).accessibilityIdentifier("favorites.notice")
      .accessibilityAddTraits(.updatesFrequently)
    }
  }
}
