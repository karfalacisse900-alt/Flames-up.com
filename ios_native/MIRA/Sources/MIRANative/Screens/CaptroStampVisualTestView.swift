#if DEBUG
import SwiftUI

/// Offline QA only. Uses the same production component, no live writes or payments.
public struct CaptroStampVisualTestView: View {
  @State private var index = 0
  @State private var opened = false
  public init() {}
  private let kinds: [CaptroStampKind] = [.social, .club, .event, .meetup, .deal]
  private var content: CaptroStampContent {
    let kind = kinds[index / 3]
    return CaptroStampContent(kind: kind, title: kind == .deal ? "15% off" : "A quiet afternoon", metadata: "Test location",
      description: "Offline QA fixture", footer: nil, actionTitle: nil, contributors: [],
      variant: kind.stampVariants[index % 3], terms: kind == .deal ? "$20 minimum spend" : "$8/month",
      availability: kind == .deal ? "Expired" : nil, relationship: kind == .deal ? "Saved" : nil,
      postID: "test-post", attachmentID: kind == .social ? nil : "test-attachment", dateMonth: "SEP", dateDay: "26")
  }
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          ForEach(0..<3) { background in
            ZStack(alignment: .bottomLeading) {
              (background == 0 ? Color.white : background == 1 ? Color.black : Color.gray)
              if background == 2 {
                HStack(spacing: 2) {
                  ForEach(0..<16) { n in (n.isMultiple(of: 2) ? Color.brown : Color.green).opacity(0.5) }
                }
              }
              CaptroPostStamp(content: content, onOpen: { opened = true }, compact: true)
                .frame(width: 232).padding(12)
            }.frame(height: 135)
          }
          CaptroPostStamp(content: content).padding(.horizontal, 12)
          Button("Next style") { index = (index + 1) % 15 }.accessibilityIdentifier("stamp.next")
        }.padding(12)
      }
      .navigationTitle(content.resolvedVariant)
      .sheet(isPresented: $opened) {
        VStack { Text(content.accessibleStampLabel); Button("Close") { opened = false } }.padding()
      }
    }
  }
}
#endif
