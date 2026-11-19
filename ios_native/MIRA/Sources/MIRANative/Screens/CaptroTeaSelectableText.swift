import SwiftUI
import UIKit

extension CaptroTeaReplyTarget {
  func selection(_ range: NSRange) -> CaptroTeaReplyTarget? {
    guard range.length > 0, let selected = Range(range, in: quote) else { return nil }
    let excerpt = String(quote[selected])
    guard !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let offset = start + quote[..<selected.lowerBound].unicodeScalars.count
    let finish = offset + excerpt.unicodeScalars.count
    return .init(id: "\(version):\(offset):\(finish)", version: version, start: offset, end: finish, quote: excerpt)
  }

  func contains(_ other: CaptroTeaReplyTarget) -> Bool {
    version == other.version && start <= other.start && end >= other.end
  }
}

// UITextView provides the actual native selection range. A SwiftUI contextMenu
// on a List row only knows the containing Text, not the user's selected excerpt.
struct CaptroTeaSelectableText: UIViewRepresentable {
  let sentence: CaptroTeaReplyTarget
  let reply: (CaptroTeaReplyTarget) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.isEditable = false
    view.isScrollEnabled = false
    view.isSelectable = true
    view.backgroundColor = .clear
    view.textColor = .label
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.adjustsFontForContentSizeCategory = true
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.delegate = context.coordinator
    return view
  }
  func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.parent = self
    if view.text != sentence.quote { view.text = sentence.quote }
    view.font = UIFont.preferredFont(forTextStyle: .callout)
    view.accessibilityIdentifier = "tea.sentence." + sentence.id
    view.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Reply to this part") { _ in
      reply(sentence); return true
    }]
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0 else { return nil }
    return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
  }
  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: CaptroTeaSelectableText
    init(_ parent: CaptroTeaSelectableText) { self.parent = parent }
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
      guard let target = parent.sentence.selection(range) else { return UIMenu(children: suggestedActions) }
      let action = UIAction(title: "Reply to this part", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self, weak textView] _ in
        self?.parent.reply(target)
        textView?.selectedTextRange = nil
        textView?.resignFirstResponder()
      }
      return UIMenu(children: [action] + suggestedActions)
    }
  }
}
