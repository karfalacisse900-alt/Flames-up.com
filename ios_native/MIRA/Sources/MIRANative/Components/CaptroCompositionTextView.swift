import SwiftUI
import UIKit

/// Non-scrolling native editor. Identical text is never reassigned, preserving cursor/IME.
struct CaptroCompositionTextView: UIViewRepresentable {
  @Binding var text: String
  @Binding var focused: Bool
  var fontSize: CGFloat
  var placeholder: String

  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator
    view.backgroundColor = .clear
    view.isScrollEnabled = false
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.keyboardDismissMode = .interactive
    view.accessibilityLabel = "Writing"
    view.accessibilityIdentifier = "composer.writing"
    return view
  }

  func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.parent = self
    if view.text != text && view.markedTextRange == nil {
      let selection = view.selectedRange
      view.text = text
      view.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
    }
    view.font = .systemFont(ofSize: fontSize)
    view.textColor = .label
    view.tintColor = UIColor(MIRATheme.Color.forest)
    view.accessibilityHint = placeholder
    if focused && !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
    if !focused && view.isFirstResponder { view.resignFirstResponder() }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0 else { return nil }
    return CGSize(width: width, height: max(fontSize * 4.5,
      uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: CaptroCompositionTextView
    init(_ parent: CaptroCompositionTextView) { self.parent = parent }
    func textViewDidChange(_ view: UITextView) {
      guard view.markedTextRange == nil else { return }
      let value = String(view.text.prefix(500))
      if view.text != value { view.text = value }
      parent.text = value
      view.invalidateIntrinsicContentSize()
      // Let the outer scroll view keep the native insertion point above the keyboard.
      DispatchQueue.main.async {
        guard let selection = view.selectedTextRange else { return }
        var ancestor = view.superview
        while let candidate = ancestor, !(candidate is UIScrollView) { ancestor = candidate.superview }
        if let scroll = ancestor as? UIScrollView {
          let caret = view.convert(view.caretRect(for: selection.end).insetBy(dx: 0, dy: -12), to: scroll)
          scroll.scrollRectToVisible(caret, animated: false)
        }
      }
    }
    func textViewDidBeginEditing(_ view: UITextView) { parent.focused = true }
    func textViewDidEndEditing(_ view: UITextView) { parent.focused = false }
  }
}

/// Compact chips wrap rather than clipping at accessibility text sizes.
struct CaptroCompositionChipLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    layout(width: proposal.width ?? 320, subviews: subviews).size
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = layout(width: bounds.width, subviews: subviews)
    for (index, origin) in result.origins.enumerated() {
      subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
        anchor: .topLeading, proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil))
    }
  }
  private func layout(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
    var origins: [CGPoint] = []
    for subview in subviews {
      let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
      if x > 0 && x + size.width > width { y += rowHeight + 8; x = 0; rowHeight = 0 }
      origins.append(CGPoint(x: x, y: y))
      x += min(size.width, width) + 8
      rowHeight = max(rowHeight, size.height)
    }
    return (CGSize(width: width, height: y + rowHeight), origins)
  }
}

