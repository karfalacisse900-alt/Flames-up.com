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
  var thread: CaptroTeaInlineThread? = nil
  var expanded = false
  var toggle: (() -> Void)? = nil

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
    let font = MIRATheme.TextStyle.body.uiFont(compatibleWith: view.traitCollection)
    let text = NSMutableAttributedString(string: sentence.quote, attributes: [.font: font, .foregroundColor: UIColor.label])
    if let thread, thread.count > 0 {
      let purple = UIColor(CaptroTeaStyle.accent)
      let link = URL(string: "captro-thread://toggle")!
      for item in thread.targets {
        let scalars = sentence.quote.unicodeScalars
        let lower = item.target.start - sentence.start, upper = item.target.end - sentence.start
        guard lower >= 0, upper <= scalars.count, lower < upper else { continue }
        let a = scalars.index(scalars.startIndex, offsetBy: lower)
        let b = scalars.index(scalars.startIndex, offsetBy: upper)
        text.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
          .underlineColor: purple.withAlphaComponent(0.4), .link: link], range: NSRange(a..<b, in: sentence.quote))
      }
      text.append(NSAttributedString(string: "\u{202F}\(thread.count)", attributes: [
        .font: UIFont.systemFont(ofSize: font.pointSize * 0.65, weight: .semibold),
        .baselineOffset: font.pointSize * 0.34, .foregroundColor: purple, .link: link]))
    }
    view.linkTextAttributes = [:]
    if !view.attributedText.isEqual(to: text) { view.attributedText = text }
    view.accessibilityIdentifier = "tea.sentence." + sentence.id
    view.accessibilityLabel = sentence.quote
    view.accessibilityValue = thread.map { $0.count > 0 ? "\($0.count) replies, \(expanded ? "expanded" : "collapsed")" : "" }
    view.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Reply to this part") { _ in
      reply(sentence); return true
    }]
    if let thread, thread.count > 0 {
      view.accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: "\(expanded ? "Collapse" : "Expand") \(thread.count) replies") { _ in
        toggle?(); return true
      })
    }
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0 else { return nil }
    return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
  }
  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: CaptroTeaSelectableText
    init(_ parent: CaptroTeaSelectableText) { self.parent = parent }
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
      if URL.scheme == "captro-thread" { parent.toggle?(); return false }
      return false
    }
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
      let captionRange = NSIntersectionRange(range, NSRange(location: 0, length: (parent.sentence.quote as NSString).length))
      guard let target = parent.sentence.selection(captionRange) else { return UIMenu(children: suggestedActions) }
      let action = UIAction(title: "Reply to this part", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self, weak textView] _ in
        self?.parent.reply(target)
        textView?.selectedTextRange = nil
        textView?.resignFirstResponder()
      }
      return UIMenu(children: [action] + suggestedActions)
    }
  }
}
