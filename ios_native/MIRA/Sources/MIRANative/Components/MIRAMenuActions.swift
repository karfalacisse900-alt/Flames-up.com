import Foundation

func MIRARunAfterMenuDismiss(_ action: @escaping () -> Void) {
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: action)
}
